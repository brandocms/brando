defmodule Brando.SSG.LocalDeliveryTest do
  use Brando.ConnCase

  alias Brando.Plug.SiteAssets
  alias Brando.Sites.DeployConfig
  alias Brando.SSG.Builds
  alias Brando.SSG.Context
  alias Brando.SSG.Deploy
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry
  alias Brando.Worker.SSGBuild

  defmodule PagesBuilder do
    @moduledoc false
    def build(_site, _environment, opts) do
      File.mkdir_p!(opts[:output_path])
      File.write!(Path.join(opts[:output_path], "index.html"), "auto")
      {:ok, %{file_count: 1, total_size: 4, url_count: 1, processed_urls: 1, failed_urls: []}}
    end
  end

  defmodule SchemaCloner do
    @moduledoc false
    @behaviour Brando.Environments.SchemaCloner

    @impl true
    def clone_schema(_source_prefix, target_prefix), do: Brando.Environments.Schema.create(target_prefix)
  end

  defmodule StatFirstAdapter do
    @moduledoc false
    # The test adapter, but `send_file/6` reads the file's info first and
    # matches `{:ok, _}`, as Bandit does: a missing file raises `MatchError`
    @behaviour Plug.Conn.Adapter

    alias Plug.Adapters.Test.Conn, as: Test

    def send_file(payload, status, headers, path, offset, length) do
      {:ok, _info} = :file.read_file_info(path)
      Test.send_file(payload, status, headers, path, offset, length)
    end

    defdelegate send_resp(payload, status, headers, body), to: Test
    defdelegate send_chunked(payload, status, headers), to: Test
    defdelegate chunk(payload, body), to: Test
    defdelegate read_req_body(payload, opts), to: Test
    defdelegate push(payload, path, headers), to: Test
    defdelegate inform(payload, status, headers), to: Test
    defdelegate upgrade(payload, protocol, opts), to: Test
    defdelegate get_peer_data(payload), to: Test
    defdelegate get_sock_data(payload), to: Test
    defdelegate get_ssl_data(payload), to: Test
    defdelegate get_http_protocol(payload), to: Test
  end

  setup do
    root = Path.join(System.tmp_dir!(), "brando-local-delivery-#{System.unique_integer([:positive])}")
    put_test_env(:tenancy_mode, :multi)
    put_test_env(:sites_path, Path.join(root, "sites"))
    put_test_env(:media_path, Path.join(root, "media"))
    put_test_env(:site_assets_path, Path.join(root, "site_assets"))
    put_test_env(:release_static_path, Path.join(root, "release"))
    Cache.clear()

    on_exit(fn ->
      File.rm_rf(root)
      Cache.clear()
    end)

    key = "local-acme-#{System.unique_integer([:positive])}"

    {:ok, site} =
      Registry.create_site(%{
        name: "Local Acme",
        key: key,
        languages: ["en", "no"],
        default_language: "en",
        status: :active,
        delivery_mode: :static,
        deploy_config: %{strategy: :local, retention_count: 1}
      })

    {:ok, live} =
      Registry.create_environment(site, %{name: "Production", key: "production", domain: "#{key}.test", live: true},
        actor: :system
      )

    {:ok, staging} =
      Registry.create_environment(site, %{name: "Staging", key: "staging", domain: "staging-#{key}.test"}, actor: :system)

    %{site: Registry.get_site(site.id), live: live, staging: staging, host: "#{key}.test", root: root}
  end

  # A build with pages, a 404 page, Markdown, a sitemap, assets and redirects
  defp ready_build(context, files \\ %{}) do
    build =
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, build} = Builds.request_build(context.site, context.live, [])
        build
      end)

    defaults = %{
      "index.html" => "home #{build.version}",
      "about/index.html" => "about #{build.version}",
      "about.md" => "# About",
      "404.html" => "missing #{build.version}",
      "robots.txt" => "User-agent: *",
      "sitemaps/sitemap.xml.gz" => :zlib.gzip("<urlset/>"),
      "manifest.json" => Jason.encode!(%{"main.js" => %{"file" => "assets/main-abc123.js"}}),
      "assets/main-abc123.js" => "console.log(1)",
      "assets/logo.svg" => "<svg/>",
      "old/index.html" => "about #{build.version}",
      "news/index.html" => "news",
      "media/image.jpg" => "copied media",
      "_redirects.json" =>
        Jason.encode!(%{
          "version" => 1,
          "redirects" => [
            %{
              "kind" => "listed",
              "source" => "/old",
              "target" => "/about",
              "status" => 301,
              "exact" => true,
              "pattern" => "/old$",
              "language" => nil
            },
            %{
              "kind" => "rule",
              "source" => "/news/:slug",
              "target" => "/articles/:slug",
              "status" => 302,
              "exact" => false,
              "pattern" => "/news/:slug",
              "language" => "en"
            },
            %{
              "kind" => "rule",
              "source" => "/no/gammel",
              "target" => "/no/ny",
              "status" => 301,
              "exact" => true,
              "pattern" => "/no/gammel$",
              "language" => "no"
            },
            %{
              "kind" => "rule",
              "source" => "/gone",
              "target" => nil,
              "status" => 410,
              "exact" => true,
              "pattern" => "/gone$",
              "language" => "en"
            },
            %{
              "kind" => "rule",
              "source" => "/news",
              "target" => "/articles",
              "status" => 301,
              "exact" => false,
              "pattern" => "/news",
              "language" => "en"
            }
          ]
        })
    }

    for {relative, content} <- Map.merge(defaults, files), content != nil do
      path = Path.join(build.build_path, relative)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, content)
    end

    {:ok, ready} = Builds.update(build, %{status: :ready, built_at: DateTime.utc_now()})
    ready
  end

  defp deploy!(build) do
    assert {:ok, deployed} = Deploy.deploy(build)
    deployed
  end

  defp request(method \\ :get, host, path) do
    method
    |> build_conn(path)
    |> Map.put(:host, host)
    |> SiteAssets.call([])
  end

  # Through an installation's endpoint: asset sets, static files, the tenant
  # plug and the router
  defp dispatch(method \\ :get, host, path, headers \\ []),
    do: dispatch_to(Brando.Test.LocalDeliveryEndpoint, method, host, path, headers)

  defp dispatch_to(endpoint, method, host, path, headers \\ []) do
    headers
    |> Enum.reduce(Map.put(build_conn(), :host, host), fn {name, value}, conn -> put_req_header(conn, name, value) end)
    |> Phoenix.ConnTest.dispatch(endpoint, method, path, nil)
  end

  describe "with one site" do
    setup context do
      Brando.Test.LocalDeliveryEndpoint.start()
      put_test_env(:tenancy_mode, :single)
      put_test_env(:site_key, context.site.key)
      Cache.warm()
      %{build: context |> ready_build() |> deploy!()}
    end

    test "answers from the build on the live domain, the endpoint's host and any other host", context do
      for host <- [context.host, "endpoint.test", "10.0.0.1", context.host <> ".", String.upcase(context.host)] do
        conn = dispatch(host, "/about")
        assert conn.status == 200, host
        assert conn.resp_body == "about v1", host
        assert dispatch(host, "/unpublished").resp_body == "missing v1", host
      end
    end

    test "answers from the build on the endpoint's host when the live environment has no domain", context do
      {:ok, _live} = Registry.update_environment(context.live, %{domain: nil}, actor: :system)

      assert dispatch("endpoint.test", "/about").resp_body == "about v1"
    end

    test "leaves a host to Phoenix that resolves to an environment that is not live", context do
      assert dispatch("staging-#{context.site.key}.test", "/about").resp_body == "dynamic /about in staging"
    end

    test "leaves the admin's page and its bundles to Phoenix", context do
      write_release_file("assets/admin/admin-abc123.js", "admin bundle")

      admin = dispatch(context.host, "/admin")
      refute admin.resp_body == "missing v1"
      assert admin.status in [200, 302]

      bundle = dispatch(context.host, "/assets/admin/admin-abc123.js")
      assert bundle.status == 200
      assert bundle.resp_body == "admin bundle"
    end

    # So the operator can open the Publishing screen and deploy again
    test "with the build's directory gone, the admin's bundles still load", context do
      write_release_file("assets/admin/admin-abc123.js", "admin bundle")
      File.rm_rf!(context.build.build_path)

      assert dispatch(context.host, "/about").status == 503

      bundle = dispatch(context.host, "/assets/admin/admin-abc123.js")
      assert bundle.status == 200
      assert bundle.resp_body == "admin bundle"
    end

    # What a blue/green deploy polls from the server before it switches
    test "leaves /health to the health plug", context do
      for host <- [context.host, "localhost"] do
        conn = dispatch(host, "/health")
        assert conn.status == 200, host
        assert %{"status" => "ok"} = Jason.decode!(conn.resp_body)
      end
    end

    test "redirects a redirect host to the domain first", context do
      {:ok, _live} =
        Registry.update_environment(context.live, %{redirect_hosts: ["www.#{context.host}"]}, actor: :system)

      conn = dispatch("www.#{context.host}", "/about")
      assert conn.status == 301
      assert get_resp_header(conn, "location") == ["http://#{context.host}/about"]
    end
  end

  describe "through the endpoint, with several sites" do
    setup context do
      Brando.Test.LocalDeliveryEndpoint.start()
      context |> ready_build() |> deploy!()
      :ok
    end

    test "a page the environment has but the build lacks is the build's 404 page", context do
      # The staging host answers it dynamically
      assert dispatch("staging-#{context.site.key}.test", "/unpublished").resp_body == "dynamic /unpublished in staging"

      conn = dispatch(context.host, "/unpublished")
      assert conn.status == 404
      assert conn.resp_body == "missing v1"
    end

    test "the IndexNow key file reaches Phoenix while IndexNow is on", context do
      prefix = Brando.Tenant.prefix(context.site, context.live)
      Brando.Environments.Schema.create(prefix)
      Repo.query!(~s|CREATE TABLE "#{prefix}".sites_indexnow (LIKE public.sites_indexnow INCLUDING ALL)|)
      {:ok, settings} = Brando.Tenant.with_prefix(prefix, &Brando.IndexNow.enable/0)

      conn = dispatch(context.host, "/#{settings.key}.txt")
      assert conn.status == 200
      assert conn.resp_body == settings.key

      # Any other key is a path the build lacks
      assert dispatch(context.host, "/#{Brando.IndexNow.generate_key()}.txt").resp_body == "missing v1"
    end

    test "a live switch leaves the public domain on the published build", context do
      put_test_env(:environment_schema_cloner, SchemaCloner)
      Brando.Environments.Schema.create(Brando.Tenant.prefix(context.site, context.live))

      assert {:ok, %{live: true}} = Brando.Environments.set_live(context.staging, creator: :system)

      conn = dispatch(context.host, "/about")
      assert conn.status == 200
      assert conn.resp_body == "about v1"
      assert get_resp_header(conn, "x-robots-tag") == []

      # The outgoing environment answers dynamically on the domain it took
      assert dispatch("staging-#{context.site.key}.test", "/about").resp_body == "dynamic /about in production"
    end

    test "a POST reaches the router", context do
      conn = dispatch(:post, context.host, "/contact")
      assert conn.resp_body == "posted /contact in production"
    end

    test "the build's assets carry the cross-origin header previews need, its pages do not", context do
      asset = dispatch(context.host, "/assets/main-abc123.js")
      assert asset.resp_body == "console.log(1)"
      assert get_resp_header(asset, "access-control-allow-origin") == ["*"]

      assert get_resp_header(dispatch(context.host, "/about"), "access-control-allow-origin") == []
    end

    test "a preview and the newer assets it names reach Phoenix and the asset sets", context do
      path = Brando.SiteAssetsFixtures.create_set(context.site, "acme-next", "js-acme-next", "acme-next.css")
      {:ok, set} = Brando.Assets.SiteAssets.register_set(context.site, path, %{})
      {:ok, _staging} = Brando.Assets.SiteAssets.activate_environment_set(set.id, context.staging)

      refute dispatch(context.host, "/__livepreview").resp_body == "missing v1"

      # A newer build's preview, on the public host
      preview = ready_build(context, %{"about/index.html" => "about next"})
      assert dispatch(context.host, "/__ssg_preview__/#{preview.preview_token}/about").resp_body =~ "about next"

      asset = dispatch(context.host, "/assets/acme-next.js")
      assert asset.status == 200
      assert asset.resp_body == "js-acme-next"
      assert get_resp_header(asset, "access-control-allow-origin") == ["*"]
    end

    test "a release file the build lacks answers from the release, a file no one has is the build's 404", context do
      write_release_file("js/app-abc123.js", "release")

      assert dispatch(context.host, "/js/app-abc123.js").resp_body == "release"

      missing = dispatch(context.host, "/js/missing.js")
      assert missing.status == 404
      assert missing.resp_body == "missing v1"
    end
  end

  describe "a request let through for a plug before the router" do
    setup context do
      Brando.Test.LocalDeliveryEndpoint.start()
      Brando.Test.LocalDeliveryNarrowEndpoint.start()
      context |> ready_build() |> deploy!()
      :ok
    end

    test "a file the release has, but the endpoint's Plug.Static does not serve, is the build's 404", context do
      put_test_env(:web_module, Brando.Test.LocalDeliveryWeb)
      write_release_file("js/app-abc123.js", "release js")
      write_release_file("css/app-abc123.css", "release css")

      # static_paths/0 says js/, the endpoint's only: does not
      missing = dispatch_to(Brando.Test.LocalDeliveryNarrowEndpoint, :get, context.host, "/js/app-abc123.js")
      assert missing.status == 404
      assert missing.resp_body == "missing v1"

      assert dispatch_to(Brando.Test.LocalDeliveryNarrowEndpoint, :get, context.host, "/css/app-abc123.css").resp_body ==
               "release css"
    end

    test "a file under a prefix static_paths/0 leaves out is the build's 404", context do
      put_test_env(:web_module, Brando.Test.LocalDeliveryWeb)
      put_test_env(Brando.Test.LocalDeliveryWeb, ~w(css js))
      write_release_file("fonts/body.woff2", "font")
      write_release_file("js/app-abc123.js", "release js")

      fonts = dispatch(context.host, "/fonts/body.woff2")
      assert fonts.status == 404
      assert fonts.resp_body == "missing v1"
      assert dispatch(context.host, "/js/app-abc123.js").resp_body == "release js"
    end

    test "an encoded prefix the router decodes is the build's 404, not the page Phoenix renders", context do
      write_release_file("assets/new.html", "release page")

      for path <- ["/%61ssets/new.html", "/%61ssets/new.html?vsn=d"] do
        conn = dispatch(context.host, path)
        assert conn.status == 404, path
        assert conn.resp_body == "missing v1", path
      end
    end

    test "/health without the health plug is the build's 404", context do
      conn = dispatch_to(Brando.Test.LocalDeliveryNarrowEndpoint, :get, context.host, "/health")
      assert conn.status == 404
      assert conn.resp_body == "missing v1"
    end

    test "a request local delivery never saw passes the tenant plug as before", context do
      assert dispatch("staging-#{context.site.key}.test", "/js/missing.js").resp_body ==
               "dynamic /js/missing.js in staging"
    end
  end

  defp write_release_file(relative, content) do
    path = Path.join(Brando.Assets.SiteAssets.Capture.release_root(), relative)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
  end

  describe "a published build" do
    test "answers its files on the live host, and a deploy or rollback switches it without a restart", context do
      first = context |> ready_build() |> deploy!()

      assert Registry.get_site(context.site.id).published_build == "v1"

      conn = request(context.host, "/")
      assert conn.halted
      assert conn.status == 200
      assert sent_body(conn) == "home v1"

      second = context |> ready_build() |> deploy!()
      assert sent_body(request(context.host, "/about")) == "about v2"
      assert sent_body(request(context.host, "/about/")) == "about v2"

      assert {:ok, _} = Deploy.rollback(context.site, Builds.get_build(first.id))
      assert sent_body(request(context.host, "/about")) == "about v1"
      assert Builds.get_build(second.id).status == :archived
    end

    test "answers a path the build lacks with its 404 page", context do
      context |> ready_build() |> deploy!()

      conn = request(context.host, "/unpublished-page")
      assert conn.halted
      assert conn.status == 404
      assert sent_body(conn) == "missing v1"
      assert get_resp_header(conn, "cache-control") == ["no-cache"]
    end

    test "reports each request it answers as a telemetry event", context do
      context |> ready_build() |> deploy!()
      test_pid = self()
      handler = "local-delivery-#{System.unique_integer([:positive])}"

      :telemetry.attach(
        handler,
        [:brando, :ssg, :local_delivery, :stop],
        fn _event, measurements, metadata, _config -> send(test_pid, {:served, measurements, metadata}) end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler) end)

      request(context.host, "/about")
      request(context.host, "/missing")

      assert_received {:served, %{duration: duration}, %{site_key: site_key, path: "/about", status: 200}}
      assert is_integer(duration) and duration >= 0
      assert site_key == context.site.key
      assert_received {:served, _measurements, %{path: "/missing", status: 404}}

      # Not for a request that passes on to Phoenix
      request(:post, context.host, "/contact")
      refute_received {:served, _measurements, %{path: "/contact"}}
    end

    test "answers a plain 404 when the build has no 404 page", context do
      context |> ready_build(%{"404.html" => nil}) |> deploy!()

      conn = request(context.host, "/missing")
      assert conn.halted
      assert conn.status == 404
      assert conn.resp_body == "Not found"
    end

    test "does not serve its redirect list", context do
      context |> ready_build() |> deploy!()

      conn = request(context.host, "/_redirects.json")
      assert conn.status == 404
      assert sent_body(conn) == "missing v1"
    end

    test "sends HTML and root files with an ETag to revalidate, and answers a match with 304", context do
      context |> ready_build() |> deploy!()

      conn = request(context.host, "/")
      assert get_resp_header(conn, "cache-control") == ["no-cache"]
      assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
      assert [etag] = get_resp_header(conn, "etag")

      fresh =
        :get
        |> build_conn("/")
        |> Map.put(:host, context.host)
        |> put_req_header("if-none-match", etag)
        |> SiteAssets.call([])

      assert fresh.status == 304

      assert get_resp_header(request(context.host, "/robots.txt"), "content-type") == ["text/plain; charset=utf-8"]
      assert get_resp_header(request(context.host, "/about.md"), "content-type") == ["text/markdown; charset=utf-8"]
      assert get_resp_header(request(context.host, "/manifest.json"), "cache-control") == ["no-cache"]
    end

    test "gives the same file of two builds different ETags, though size and time agree", context do
      first = ready_build(context)
      second = ready_build(context)
      same_time = {{2026, 11, 16}, {12, 0, 0}}
      File.touch!(Path.join(first.build_path, "index.html"), same_time)
      File.touch!(Path.join(second.build_path, "index.html"), same_time)

      deploy!(first)
      [old_etag] = get_resp_header(request(context.host, "/"), "etag")

      deploy!(second)

      conn =
        :get
        |> build_conn("/")
        |> Map.put(:host, context.host)
        |> put_req_header("if-none-match", old_etag)
        |> SiteAssets.call([])

      assert conn.status == 200
      assert sent_body(conn) == "home v2"
    end

    test "caches what the Vite manifest lists, and a vsn request, for a year", context do
      context |> ready_build() |> deploy!()

      hashed = request(context.host, "/assets/main-abc123.js")
      assert get_resp_header(hashed, "cache-control") == ["public, max-age=31536000, immutable"]
      assert get_resp_header(hashed, "etag") == []

      plain = request(context.host, "/assets/logo.svg")
      assert get_resp_header(plain, "cache-control") == ["no-cache"]

      versioned = request(context.host, "/assets/logo.svg?vsn=d")
      assert get_resp_header(versioned, "cache-control") == ["public, max-age=31536000, immutable"]

      # A page changes with the next deploy, whatever its query
      page = request(context.host, "/about?vsn=d")
      assert get_resp_header(page, "cache-control") == ["no-cache"]
      assert [_etag] = get_resp_header(page, "etag")
    end

    test "sends its pages with the browser's security headers, and the application's own", context do
      context |> ready_build() |> deploy!()

      for path <- ["/about", "/unpublished"] do
        conn = request(context.host, path)
        assert get_resp_header(conn, "referrer-policy") == ["strict-origin-when-cross-origin"], path
        assert get_resp_header(conn, "content-security-policy") == ["base-uri 'self'; frame-ancestors 'self';"], path
        assert get_resp_header(conn, "x-content-type-options") == ["nosniff"], path
        assert get_resp_header(conn, "x-permitted-cross-domain-policies") == ["none"], path
      end

      assert get_resp_header(request(context.host, "/assets/logo.svg"), "referrer-policy") == []

      put_test_env(Brando.SSG.LocalDelivery, headers: %{"content-security-policy" => "default-src 'self'"})
      conn = request(context.host, "/about")
      assert get_resp_header(conn, "content-security-policy") == ["default-src 'self'"]
      assert get_resp_header(conn, "referrer-policy") == ["strict-origin-when-cross-origin"]
    end

    test "answers Accept: text/markdown with a page's Markdown file when the build has one", context do
      context |> ready_build() |> deploy!()

      markdown =
        :get
        |> build_conn("/about")
        |> Map.put(:host, context.host)
        |> put_req_header("accept", "text/markdown, text/html;q=0.9")
        |> SiteAssets.call([])

      assert markdown.status == 200
      assert sent_body(markdown) == "# About"
      assert get_resp_header(markdown, "content-type") == ["text/markdown; charset=utf-8"]
      assert get_resp_header(markdown, "vary") == ["Accept"]

      html = request(context.host, "/about")
      assert sent_body(html) == "about v1"
      assert get_resp_header(html, "vary") == ["Accept"]

      # The root has no Markdown file in this build: HTML, whatever is asked
      root =
        :get
        |> build_conn("/")
        |> Map.put(:host, context.host)
        |> put_req_header("accept", "text/markdown")
        |> SiteAssets.call([])

      assert sent_body(root) == "home v1"
      assert get_resp_header(root, "vary") == []
    end

    test "sends the gzipped sitemap as the sitemap controller does", context do
      context |> ready_build() |> deploy!()

      conn = request(context.host, "/sitemaps/sitemap.xml.gz")
      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/gzip"]
      assert get_resp_header(conn, "content-disposition") == [~s[attachment; filename="sitemap.xml.gz"]]
      assert :zlib.gunzip(sent_body(conn)) == "<urlset/>"
    end
  end

  describe "the build's redirects" do
    setup context do
      context |> ready_build() |> deploy!()
      :ok
    end

    test "a listed path redirects, over the page the build kept under it", context do
      conn = request(context.host, "/old")
      assert conn.status == 301
      assert get_resp_header(conn, "location") == ["/about"]
    end

    test "a rule that is not exact loses to a page the build has", context do
      assert sent_body(request(context.host, "/news")) == "news"
    end

    test "the first rule that matches answers, with its segments, in its language", context do
      conn = request(context.host, "/news/launch")
      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["/articles/launch"]

      # An English rule does not answer a Norwegian path; the Norwegian one does
      assert request(context.host, "/no/news/launch").status == 404
      assert get_resp_header(request(context.host, "/no/gammel"), "location") == ["/no/ny"]
      assert request(context.host, "/gammel").status == 404
    end

    test "a rule without a target answers 410 Gone", context do
      conn = request(context.host, "/gone")
      assert conn.status == 410
      assert get_resp_header(conn, "location") == []
    end

    test "a build made before languages were listed reads the site's current ones", context do
      set_default_language(context.site, "no")

      # `/news/launch` is now a Norwegian path, which the English rule does not answer
      assert request(context.host, "/news/launch").status == 404
    end

    test "matches the decoded path", context do
      assert get_resp_header(request(context.host, "/%6Fld"), "location") == ["/about"]
    end
  end

  describe "the languages a build was made with" do
    test "decide which rules apply, whatever the site's languages are now", context do
      redirects =
        Jason.encode!(%{
          "version" => 1,
          "languages" => ["en", "no"],
          "default_language" => "en",
          "redirects" => [
            %{
              "kind" => "rule",
              "source" => "/news/:slug",
              "target" => "/articles/:slug",
              "status" => 302,
              "exact" => false,
              "pattern" => "/news/:slug",
              "language" => "en"
            }
          ]
        })

      context |> ready_build(%{"_redirects.json" => redirects}) |> deploy!()
      set_default_language(context.site, "no")

      conn = request(context.host, "/news/launch")
      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["/articles/launch"]
    end
  end

  # Without a deploy, and without the seeding a save runs
  defp set_default_language(site, language) do
    Repo.update_all(from(s in Brando.Sites.Site, where: s.id == ^site.id), set: [default_language: language])
    Cache.warm()
  end

  describe "what keeps reaching Phoenix" do
    setup context do
      context |> ready_build() |> deploy!()
      :ok
    end

    test "a POST", context do
      refute request(:post, context.host, "/contact").halted
      refute request(:post, context.host, "/").halted
    end

    test "media, previews, live preview and Brando's own paths", context do
      for path <- ~w(/media/image.jpg /__p__/key /__ssg_preview__/token/ /__livepreview /__brando/forms/csrf-token) do
        refute request(context.host, path).halted, path
      end
    end

    test "an application's own paths", context do
      assert request(context.host, "/api/things").status == 404
      put_test_env(Brando.SSG.LocalDelivery, dynamic_paths: ["/api"])
      refute request(context.host, "/api/things").halted
    end

    # The admin answers on the endpoint's host only with several sites
    test "the admin's paths, where the admin answers", context do
      assert request(context.host, "/admin").status == 404

      put_test_env(:tenancy_mode, :single)
      put_test_env(:site_key, context.site.key)
      Cache.warm()
      refute request(context.host, "/admin").halted
    end

    test "a request with a build's signed context, so a build is not made from the published one", context do
      token = Context.sign(context.site, context.live)

      conn =
        :get
        |> build_conn("/")
        |> Map.put(:host, context.host)
        |> put_req_header(Context.header(), token)
        |> SiteAssets.call([])

      refute conn.halted

      forged =
        :get
        |> build_conn("/")
        |> Map.put(:host, context.host)
        |> put_req_header(Context.header(), "forged")
        |> SiteAssets.call([])

      assert forged.halted
    end

    test "an environment that is not live, on its own host", context do
      refute request("staging-#{context.site.key}.test", "/").halted
    end
  end

  describe "paths that could leave the build's directory" do
    setup context do
      build = context |> ready_build() |> deploy!()
      File.write!(Path.join(context.root, "secret.html"), "secret")
      %{build: build}
    end

    test "with .. or an encoded slash or NUL answer the 404 page", context do
      for path <- ["/../../../secret.html", "/%2E%2E/%2E%2E/secret.html", "/about%2F..%2F..%2Fsecret.html", "/a%00b"] do
        conn = request(context.host, path)
        assert conn.status == 404, path
        assert sent_body(conn) == "missing v1", path
      end
    end

    test "through a symbolic link answer the 404 page", context do
      # A new version, so its files are listed after the links exist
      build = ready_build(context)
      File.ln_s!(Path.join(context.root, "secret.html"), Path.join(build.build_path, "linked.html"))
      File.ln_s!(context.root, Path.join(build.build_path, "outside"))
      deploy!(build)

      assert sent_body(request(context.host, "/linked.html")) == "missing v2"
      assert sent_body(request(context.host, "/outside/secret.html")) == "missing v2"
    end
  end

  describe "no build to serve" do
    test "before the first deploy, the host answers as it does now", context do
      context |> ready_build()
      refute request(context.host, "/").halted
    end

    test "a dynamic site's host is untouched", context do
      context |> ready_build() |> deploy!()
      {:ok, _site} = Registry.update_site(context.site, %{delivery_mode: :dynamic})

      refute request(context.host, "/").halted
      assert Registry.get_site(context.site.id).published_build == nil
    end

    test "switching the strategy away stops serving at once, and switching back serves nothing until a deploy",
         context do
      context |> ready_build() |> deploy!()
      put_test_env(DeployConfig, s3_targets: ["s3://bucket/{site_key}"])

      {:ok, site} =
        Registry.update_site(context.site, %{deploy_config: %{strategy: :s3, target: "s3://bucket/#{context.site.key}"}})

      refute request(context.host, "/").halted

      {:ok, _site} = Registry.update_site(site, %{deploy_config: %{strategy: :local}})
      refute request(context.host, "/").halted
    end

    test "archiving or deleting the site stops serving at once", context do
      context |> ready_build() |> deploy!()
      assert request(context.host, "/").halted

      {:ok, site} = Registry.update_site(context.site, %{status: :archived})
      refute request(context.host, "/").halted

      {:ok, site} = Registry.update_site(site, %{status: :active})
      assert request(context.host, "/").halted

      {:ok, _deleted} = Registry.delete_site(site)
      refute request(context.host, "/").halted
    end

    test "with tenancy off nothing is served", context do
      context |> ready_build() |> deploy!()
      put_test_env(:tenancy_mode, :none)
      Cache.warm()

      refute request(context.host, "/").halted
    end
  end

  describe "deploying" do
    test "needs no target, and is refused once the site no longer serves itself", context do
      build = ready_build(context)
      put_test_env(DeployConfig, s3_targets: ["s3://bucket/{site_key}"])

      {:ok, _site} =
        Registry.update_site(context.site, %{deploy_config: %{strategy: :s3, target: "s3://bucket/#{context.site.key}"}})

      assert {:error, :local_delivery_not_configured} = Deploy.deploy(build)
    end

    test "a rollback to a build made for another delivery is refused, and copies nothing", context do
      served = context |> ready_build() |> deploy!()
      older = ready_build(context)

      {:ok, older} =
        Builds.update(older, %{
          status: :archived,
          deploy_config: %{"strategy" => "rsync", "target" => "deploy@example.com:/srv/www"}
        })

      runner = fn _cmd, _args, _opts -> flunk("rsync ran") end

      assert {:error, :build_made_for_another_delivery} =
               Deploy.rollback(context.site, Builds.get_build(older.id), runner: runner)

      assert Builds.get_build(older.id).status == :archived
      assert Builds.get_build(served.id).status == :deployed
      assert Registry.get_site(context.site.id).published_build == served.version

      assert {:cancel, :build_made_for_another_delivery} =
               perform_job(Brando.Worker.SSGDeploy, %{"build_id" => older.id, "action" => "rollback"})

      assert Builds.get_build(older.id).build_log =~ "made for another delivery"
    end

    test "is refused when the installation turns local delivery off", context do
      build = ready_build(context)
      put_test_env(DeployConfig, local_delivery: false)

      assert {:error, :local_delivery_disabled} = Deploy.deploy(build)
      assert Registry.get_site(context.site.id).published_build == nil
    end

    test "deploys automatically after a successful build", context do
      put_test_env(:ssg_builder, PagesBuilder)

      build =
        Oban.Testing.with_testing_mode(:manual, fn ->
          {:ok, build} = Builds.request_build(context.site, context.live, auto_deploy: true)
          build
        end)

      assert build.auto_deploy
      assert :ok = perform_job(SSGBuild, %{"build_id" => build.id})
      assert Builds.get_build(build.id).status == :deployed
      assert sent_body(request(context.host, "/")) == "auto"
    end

    test "retention never prunes the published build", context do
      first = context |> ready_build() |> deploy!()
      second = context |> ready_build() |> deploy!()
      third = ready_build(context)

      # Published, though no longer marked deployed (a build deployed
      # elsewhere since): only the published version keeps it
      {:ok, _} = Builds.update(Builds.get_build(second.id), %{status: :archived})
      assert {:ok, pruned} = Deploy.prune(context.site, 1)

      assert Enum.map(pruned, & &1.id) == [first.id]
      assert File.dir?(second.build_path)
      assert File.dir?(third.build_path)
      assert sent_body(request(context.host, "/")) == "home v2"
    end
  end

  describe "a build directory that goes missing" do
    test "answers 503 once the files are gone, though memory still lists them", context do
      build = context |> ready_build() |> deploy!()
      assert sent_body(request(context.host, "/about")) == "about v1"

      File.rm_rf!(build.build_path)

      conn = request(context.host, "/about")
      assert conn.status == 503
      assert get_resp_header(conn, "retry-after") == ["60"]
      assert request(context.host, "/").status == 503
    end

    test "answers 503 whichever error the server's adapter raises for a missing file", context do
      build = context |> ready_build() |> deploy!()
      assert sent_body(request(context.host, "/about")) == "about v1"

      File.rm_rf!(build.build_path)

      for _ <- 1..2 do
        conn =
          :get
          |> build_conn("/about")
          |> Map.put(:host, context.host)
          |> Map.update!(:adapter, fn {_test, payload} -> {StatFirstAdapter, payload} end)
          |> SiteAssets.call([])

        assert conn.status == 503
      end
    end

    test "is looked for and logged once per interval, not on every request", context do
      build = context |> ready_build() |> deploy!()
      File.rm_rf!(build.build_path)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          for _ <- 1..5, do: assert(request(context.host, "/about").status == 503)
        end)

      assert length(String.split(log, "has no published build to serve")) == 2
    end
  end

  describe "pruning" do
    # Chosen under the lock, so a rollback on another node that publishes an
    # archived build finishes first, or finds it pruned and is refused. A build
    # job does not wait behind another node's deploy: the next build prunes.
    test "is skipped while a deploy or rollback holds the lock, and the build's log says so", context do
      put_test_env(:ssg_builder, PagesBuilder)
      first = context |> ready_build() |> deploy!()
      _second = context |> ready_build() |> deploy!()
      _third = context |> ready_build() |> deploy!()

      key = "ssg-deploy:#{context.site.id}"
      lock = lock_elsewhere(key)

      assert Deploy.prune(Registry.get_site(context.site.id), 1) == :skipped
      assert File.dir?(first.build_path)

      build =
        Oban.Testing.with_testing_mode(:manual, fn ->
          {:ok, build} = Builds.request_build(context.site, context.live, [])
          build
        end)

      assert :ok = perform_job(SSGBuild, %{"build_id" => build.id})
      assert Builds.get_build(build.id).build_log =~ "Artifact pruning skipped"
      assert File.dir?(first.build_path)

      Postgrex.query!(lock, "SELECT pg_advisory_unlock(hashtextextended($1, 0))", [key])
      assert {:ok, pruned} = Deploy.prune(Registry.get_site(context.site.id), 1)
      assert first.id in Enum.map(pruned, & &1.id)
      refute File.dir?(first.build_path)
    end

    test "a rollback that waited for it finds the build pruned, and the published build keeps answering", context do
      first = context |> ready_build() |> deploy!()
      _second = context |> ready_build() |> deploy!()
      third = context |> ready_build() |> deploy!()

      assert {:ok, [%{id: pruned_id}]} = Deploy.prune(Registry.get_site(context.site.id), 1)
      assert pruned_id == first.id

      # The rollback was asked for with the build as it was before pruning
      assert {:error, :build_not_deployable} = Deploy.rollback(context.site, first)

      assert Registry.get_site(context.site.id).published_build == third.version
      assert Builds.get_build(third.id).status == :deployed
      assert sent_body(request(context.host, "/about")) == "about v3"
    end
  end

  # A session of its own, outside the sandbox, as another node's
  defp lock_elsewhere(key) do
    config = Keyword.drop(Brando.Repo.repo().config(), [:pool, :ownership_pool, :pool_size, :name])
    {:ok, conn} = Postgrex.start_link(config)
    Postgrex.query!(conn, "SELECT pg_advisory_lock(hashtextextended($1, 0))", [key])
    conn
  end

  describe "the deploy settings" do
    test "need no target or operator's list for local delivery with several sites", context do
      put_test_env(DeployConfig, [])
      changeset = DeployConfig.changeset(%DeployConfig{}, %{strategy: :local, target: "ignored"}, context.site.key)

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :target) == nil
    end

    test "refuse local delivery when the installation turns it off", context do
      put_test_env(DeployConfig, local_delivery: false)
      changeset = DeployConfig.changeset(%DeployConfig{}, %{strategy: :local}, context.site.key)

      refute changeset.valid?
      assert changeset.errors[:strategy]
    end
  end

  # Plug.Test reads what `send_file/3` sends into the body
  defp sent_body(%Plug.Conn{resp_body: body}), do: body
end

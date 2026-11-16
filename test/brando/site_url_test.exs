# What a generated page controller and layout write into a site's head:
# meta, JSON-LD and the canonical and alternate links
defmodule Brando.SiteURLTest.PageController do
  use Phoenix.Controller, formats: [:html]

  import Phoenix.Component, only: [sigil_H: 2]
  import Brando.HTML, only: [render_meta: 1, render_json_ld: 1, render_hreflangs: 1]

  alias Brando.Plug.HTML

  def index(conn, _params) do
    {:ok, page} =
      Brando.Pages.get_page(%{
        matches: %{uri: "index", language: "en"},
        status: :published,
        preload: [:alternate_entries]
      })

    conn =
      conn
      |> HTML.put_meta(Brando.Pages.Page, page)
      |> HTML.put_hreflang(page)
      |> HTML.put_json_ld(:breadcrumbs, [{"Home", "/"}, {"About", "/about"}])

    assigns = %{conn: conn}

    head =
      ~H"""
      <.render_meta conn={@conn} />
      <.render_json_ld conn={@conn} />
      <.render_hreflangs conn={@conn} />
      """
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    send_resp(conn, 200, "<html><head>#{head}</head><body></body></html>")
  end

  # A CMS page at its path, as the generated page controller shows it
  def show(conn, %{"path" => path}) do
    {language, parsed_path} = Brando.I18n.parse_path(path)

    {:ok, page} =
      Brando.Pages.get_page(%{
        matches: %{path: parsed_path, language: language, has_url: true},
        status: :published,
        preload: [:alternate_entries]
      })

    conn =
      conn
      |> HTML.put_meta(Brando.Pages.Page, page)
      |> HTML.put_json_ld_type(page.json_ld_type)
      |> HTML.put_hreflang(page)
      |> HTML.put_json_ld(Brando.Pages.Page, page)

    send_resp(conn, 200, "<html><head>#{head(conn)}</head><body></body></html>")
  end

  defp head(conn) do
    assigns = %{conn: conn}

    ~H"""
    <.render_meta conn={@conn} />
    <.render_json_ld conn={@conn} />
    <.render_hreflangs conn={@conn} />
    """
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end
end

defmodule Brando.SiteURLTest.Router do
  use Phoenix.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :assign_language
    plug Brando.Plug.Tenant
  end

  scope "/" do
    pipe_through :browser
    get "/", Brando.SiteURLTest.PageController, :index
    get "/*path", Brando.SiteURLTest.PageController, :show
  end

  def assign_language(conn, _opts), do: Plug.Conn.assign(conn, :language, "en")
end

defmodule Brando.SiteURLTest do
  # The absolute URLs a site's pages carry name the host of the environment
  # rendered, not the endpoint's (the admin's)
  use Brando.ConnCase, async: false

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Brando.Pages.Page
  alias Brando.Tenant
  alias Brando.Tenant.Registry
  alias Brando.Tenant.Setup

  @prefixes ~w(tenant_acme_production tenant_acme_staging tenant_acme_lab)

  defmodule Migrator do
    @behaviour Brando.Environments.Migrator

    @impl true
    def migrate(_site, _environment), do: {:ok, []}
  end

  # A datasource whose block shows the entry chosen for it
  defmodule Chosen do
    use Brando.Blueprint,
      application: "BrandoIntegration",
      domain: "Tests",
      schema: "Chosen",
      singular: "chosen",
      plural: "chosens",
      gettext_module: Brando.Gettext

    datasources do
      datasource :chosen do
        type :single
        list(fn _module, _language, _vars -> {:ok, []} end)
        get(fn identifier -> {:ok, Brando.Repo.get(identifier.schema, identifier.entry_id)} end)
      end

      datasource :work do
        type :list
        list(fn _module, _language, _vars -> {:ok, Brando.Repo.all(Ecto.Query.where(Brando.Pages.Page, uri: "work"))} end)
      end
    end
  end

  # An endpoint on a non-default port, as in development
  defmodule PortEndpoint do
    def url, do: "http://localhost:4000"
    def struct_url, do: URI.parse(url())
  end

  defmodule RootOnly do
    import Brando.SSG

    urls :pages do
      ["/"]
    end
  end

  defmodule AboutPage do
    import Brando.SSG

    urls :pages do
      ["/en/about/"]
    end
  end

  setup do
    root = Path.join(System.tmp_dir!(), "brando-site-url-#{System.unique_integer([:positive])}")

    put_test_env(:media_path, Path.join(root, "media"))
    put_test_env(:sites_path, Path.join(root, "sites"))
    put_test_env(:tenant_migrator, Migrator)
    put_test_env(:tenant_structure_cloner, Brando.TenantCloners)
    put_test_env(:environment_schema_cloner, Brando.TenantCloners)
    put_test_env(:tenancy_mode, :multi)
    Tenant.put_prefix(nil)
    Tenant.Cache.clear()

    # Rendering fills caches from rows the sandbox rolls back
    cached = for key <- ~w(identity seo navigation)a, do: {key, Brando.Cache.get(key)}

    on_exit(fn ->
      File.rm_rf(root)
      Tenant.put_prefix(nil)
      Tenant.Cache.clear()
      Brando.TenantCaches.clear(@prefixes)
      Enum.each(cached, &restore_cache/1)
    end)

    creator = Brando.Factory.insert(:random_user, role: :superuser, avatar: nil)
    {:ok, site} = Setup.create_site(site_attrs(), creator, environments: environments())

    %{site: site, root: root}
  end

  describe "a request" do
    test "names the site's host on Production and Staging's host on Staging" do
      assert_head_names(request("acme.test").resp_body, "http://acme.test")
      assert_head_names(request("staging.acme.test").resp_body, "http://staging.acme.test")
    end
  end

  describe "a page's URL" do
    # The canonical, og:url and every JSON-LD @id and url name the page's
    # entry URL, without a trailing slash, however the page was requested
    test "is the same requested with or without a trailing slash and in a static build", context do
      for key <- ["production", "staging"], do: in_environment(key, fn -> about_page!() end)

      # The test config scopes the default language's routes: the entry's URL
      # is /en/about, and /about reaches the same page
      for path <- ["/en/about", "/en/about/", "/about/", "/en/about?ref=x"] do
        assert_one_page_url(request("acme.test", path).resp_body, "http://acme.test/en/about")
      end

      site = Registry.get_site(context.site.id)
      staging = Enum.find(site.environments, &(&1.key == "staging"))
      html = build(site, staging, context.root, AboutPage, "en/about/index.html")

      assert_one_page_url(html, "http://staging.acme.test/en/about")
    end
  end

  describe "a static build" do
    test "stores pages naming the built environment's domain, whatever origin it fetched from", context do
      site = Registry.get_site(context.site.id)
      staging = Enum.find(site.environments, &(&1.key == "staging"))

      assert_head_names(build(site, staging, context.root), "http://staging.acme.test")
    end

    test "of an environment without a domain names the live environment's", context do
      site = Registry.get_site(context.site.id)
      lab = Enum.find(site.environments, &(&1.key == "lab"))

      assert_head_names(build(site, lab, context.root), "http://acme.test")
    end
  end

  describe "a render outside a request" do
    test "names the host of the environment the tenant prefix names" do
      in_environment("staging", fn ->
        page = Brando.Repo.get_by!(Page, uri: "index", language: :en)
        assert Brando.Blueprint.URL.resolve(page, :with_host) == "http://staging.acme.test/en"
        assert Brando.ContentEvents.entry_url(page) == "http://staging.acme.test/en"
        assert Brando.SEO.Markdown.url(page) == "http://staging.acme.test/en.md"
      end)

      in_environment("production", fn ->
        assert Brando.Utils.hostname("/about") == "http://acme.test/about"
      end)
    end

    test "the public base URL is the live environment's domain in every environment" do
      for key <- ~w(production staging lab) do
        in_environment(key, fn -> assert Brando.Utils.public_hostname("/about") == "http://acme.test/about" end)
      end

      assert Brando.Utils.public_hostname() == Brando.endpoint().url()
    end

    test "the port is the endpoint URL's" do
      put_test_env(:endpoint_module, PortEndpoint)

      in_environment("staging", fn ->
        assert Brando.Utils.hostname("/about") == "http://staging.acme.test:4000/about"
        assert Brando.Utils.public_hostname("/about") == "http://acme.test:4000/about"
      end)
    end

    test "alternate links given as paths get the environment's host" do
      in_environment("staging", fn ->
        conn =
          Phoenix.ConnTest.build_conn(:get, "/en/about")
          |> Plug.Conn.assign(:language, "en")
          |> Brando.Plug.HTML.put_hreflang(en: "/en/about", no: "/no/om")

        assert Brando.Plug.HTML.hreflangs(conn) == [
                 {:en, "http://staging.acme.test/en/about"},
                 {:no, "http://staging.acme.test/no/om"}
               ]
      end)
    end

    test "alternates from a route helper stay paths for a language switcher; the head's alternates get the host" do
      in_environment("staging", fn ->
        path = Brando.I18n.Helpers.localized_path("en", :article_path, [Brando.endpoint(), :show, "slug"])
        assert "/" <> _ = path

        conn =
          Phoenix.ConnTest.build_conn(:get, path)
          |> Plug.Conn.assign(:language, "en")
          |> Brando.Plug.HTML.put_hreflang({:article_path, [Brando.endpoint(), :show, "slug"]})

        assert List.keyfind(conn.private.brando_hreflangs, :en, 0) == {:en, path}

        switcher = render_component(&Brando.HTML.alternate_url/1, conn: conn, language: :en)
        {:ok, link} = Floki.parse_fragment(switcher)
        assert Floki.attribute(link, "a", "href") == [path]

        {:ok, head} =
          render_component(&Brando.HTML.render_hreflangs/1, conn: conn) |> Floki.parse_fragment()

        # One language: its alternate is the page's URL, and a single language lists none
        assert Brando.Plug.HTML.hreflangs(conn) == [{:en, "http://staging.acme.test" <> path}]
        assert Floki.attribute(head, ~s(link[rel="alternate"][hreflang]), "href") == []
      end)
    end

    test "a content event job looks up the entry's URL on the host of the environment it was queued in" do
      {page, args} =
        in_environment("staging", fn ->
          page = Brando.Repo.get_by!(Page, uri: "index", language: :en)

          args =
            Brando.Tenant.Job.attach(%{
              "id" => Ecto.UUID.generate(),
              "type" => "entry.updated",
              "schema" => to_string(Page),
              "entry_id" => page.id
            })

          {page, args}
        end)

      :ok = Phoenix.PubSub.subscribe(Brando.pubsub(), Brando.ContentEvents.topic("tenant_acme_staging"))
      Tenant.put_prefix(nil)

      assert :ok = perform_job(Brando.Worker.ContentEventDispatcher, args)
      assert_receive {:content_event, %{entry_id: entry_id, url: "http://staging.acme.test/en"}}
      assert entry_id == page.id
    end
  end

  describe "after a live switch" do
    test "a service URL the identity cache holds names the live host", context do
      in_environment("staging", fn ->
        {:ok, identity} = Brando.Sites.get_identity(%{matches: %{language: "en"}, preload: [services: :identifier]})
        user = Brando.Factory.insert(:random_user)
        {:ok, _} = Brando.Sites.update_identity(identity, %{services: [%{name: "Strategi", url: "/strategi"}]}, user)
        assert [%{name: "Strategi"}] = Brando.Cache.Identity.get("en").services
      end)

      set_live(context.site, "staging")

      html = request("acme.test").resp_body
      assert_head_names(html, "http://acme.test")
      assert "http://acme.test/strategi" in head_urls(html)
    end

    test "block JSON-LD stored on Staging names the live host Staging now has", context do
      in_environment("staging", &store_block_json_ld/0)
      set_live(context.site, "staging")
      in_environment("staging", fn -> assert_stored_json_ld_names("http://acme.test") end)
    end
  end

  describe "when the live environment's domain changes" do
    test "the block JSON-LD every environment stored is rendered again on the new domain", context do
      user = Brando.Factory.insert(:random_user)
      pages = for key <- ~w(production staging), into: %{}, do: {key, in_environment(key, fn -> json_ld_page!(user) end)}

      for {key, page} <- pages do
        in_environment(key, fn -> assert rendered_blocks(page) =~ ~S(http:\/\/acme.test\/en\/work) end)
      end

      production = Registry.get_environment_by_key(context.site, "production")
      assert {:ok, _} = Registry.update_environment(production, %{domain: "www.acme.test"}, actor: :system)

      for {key, page} <- pages do
        in_environment(key, fn ->
          html = rendered_blocks(page)
          assert html =~ ~S(http:\/\/www.acme.test\/en\/work)
          refute html =~ ~S(http:\/\/acme.test)
        end)
      end
    end
  end

  describe "a suspended site" do
    test "keeps its public base URL, and its stored JSON-LD follows a change of its live domain", context do
      user = Brando.Factory.insert(:random_user)
      page = in_environment("staging", fn -> json_ld_page!(user) end)
      {:ok, _} = Registry.update_site(Registry.get_site(context.site.id), %{status: :suspended})

      in_environment("staging", fn -> assert Brando.Utils.public_hostname("/about") == "http://acme.test/about" end)

      production = Registry.get_environment_by_key(context.site, "production")
      assert {:ok, _} = Registry.update_environment(production, %{domain: "www.acme.test"}, actor: :system)

      in_environment("staging", fn ->
        assert rendered_blocks(page) =~ ~S(http:\/\/www.acme.test\/en\/work)
      end)
    end
  end

  describe "a live switch" do
    test "on a :static site, renders the stored block JSON-LD again on the new live environment's domain", context do
      {:ok, _} = Registry.update_site(Registry.get_site(context.site.id), %{delivery_mode: :static})
      user = Brando.Factory.insert(:random_user)
      pages = for key <- ~w(production staging), into: %{}, do: {key, in_environment(key, fn -> json_ld_page!(user) end)}

      set_live(context.site, "staging")
      assert Registry.get_environment_by_key(context.site, "staging").domain == "staging.acme.test"

      for {key, page} <- pages do
        in_environment(key, fn ->
          html = rendered_blocks(page)
          assert html =~ ~S(http:\/\/staging.acme.test\/en\/work)
          refute html =~ ~S(http:\/\/acme.test)
        end)
      end
    end

    test "on a :dynamic site, where the public base URL stays, renders nothing again", context do
      user = Brando.Factory.insert(:random_user)
      page = in_environment("production", fn -> json_ld_page!(user) end)

      jobs =
        Oban.Testing.with_testing_mode(:manual, fn ->
          set_live(context.site, "staging")
          all_enqueued(worker: Brando.Worker.EntryRenderer)
        end)

      refute Enum.any?(jobs, &(&1.args["entry_id"] == page.id))
      in_environment("production", fn -> assert rendered_blocks(page) =~ ~S(http:\/\/acme.test\/en\/work) end)
    end
  end

  describe "an entry whose stored JSON-LD has the @id form with a slash before the fragment" do
    test "has the page's form once `mix brando.entries.resave` renders it again" do
      user = Brando.Factory.insert(:random_user)

      in_environment("production", fn ->
        page = json_ld_page!(user)
        assert rendered_blocks(page) =~ ~S(http:\/\/acme.test\/en\/work#creativework")

        old = String.replace(rendered_blocks(page), "#creativework", "/#creativework")
        {1, _} = Brando.Repo.update_all(from(p in Page, where: p.id == ^page.id), set: [rendered_blocks: old])

        # What the task does for each entry
        assert {:ok, _} = Brando.Content.Blocks.render_and_store(Page, page.id, force: true)
        assert rendered_blocks(page) =~ ~S(http:\/\/acme.test\/en\/work#creativework")
        refute rendered_blocks(page) =~ "/#creativework"
      end)
    end
  end

  describe "when the live environment's domain changes on another node" do
    # This node's record of the registry writes its cache has caught up with
    @registry_tokens {Brando.Cache.Freshness, :registry}

    setup do
      tokens = Cachex.get!(:cache, @registry_tokens)

      on_exit(fn ->
        if tokens, do: Cachex.put(:cache, @registry_tokens, tokens), else: Cachex.del(:cache, @registry_tokens)
      end)
    end

    test "a render job run before this node's registry cache has the domain refreshes it first", context do
      user = Brando.Factory.insert(:random_user)
      page = in_environment("staging", fn -> json_ld_page!(user) end)
      production = Registry.get_environment_by_key(context.site, "production")

      jobs =
        Oban.Testing.with_testing_mode(:manual, fn ->
          assert {:ok, _} = Registry.update_environment(production, %{domain: "www.acme.test"}, actor: :system)
          all_enqueued(worker: Brando.Worker.EntryRenderer)
        end)

      job = Enum.find(jobs, &(&1.args["entry_id"] == page.id and &1.args["tenant_prefix"] == "tenant_acme_staging"))
      assert job

      # As on a node that has not heard of the write: its cache holds the old domain
      stale_registry_cache(production, "acme.test", "www.acme.test")
      Cachex.del(:cache, @registry_tokens)

      assert {:ok, _} = Brando.Worker.EntryRenderer.perform(job)
      in_environment("staging", fn -> assert rendered_blocks(page) =~ ~S(http:\/\/www.acme.test\/en\/work) end)
      assert Tenant.Cache.get_live_env("acme").domain == "www.acme.test"

      # Known now: the next job for the write leaves the cache as it is
      stale_registry_cache(production, "acme.test", "www.acme.test")
      assert {:ok, _} = Brando.Worker.EntryRenderer.perform(job)
      assert Tenant.Cache.get_live_env("acme").domain == "acme.test"
    end
  end

  describe "when the live environment's domain changes, an entry using a shared module" do
    test "is rendered again when the module emits JSON-LD, or the environment's override of it does", context do
      user = Brando.Factory.insert(:random_user)
      site = Registry.get_site(context.site.id)
      {:ok, shared} = Brando.Content.SharedLibrary.create_shared(:module, work_list_module(), :system)
      {:ok, plain} = Brando.Content.SharedLibrary.create_shared(:module, work_list_module("<p>Work</p>"), :system)
      :ok = Brando.Content.SharedLibrary.set_enabled(site, :module, [shared.id, plain.id])

      production_page = in_environment("production", fn -> module_page!(user, shared.id, :shared) end)

      staging_page =
        in_environment("staging", fn ->
          {:ok, override} =
            Brando.Content.SharedLibrary.customize(:module, plain.id, site, Tenant.current_prefix(), :system)

          {:ok, _} =
            Brando.Content.update_module(override.id, %{code: ~s({{ entries | json_ld: "CreativeWork" }})}, :system)

          module_page!(user, plain.id, :shared)
        end)

      in_environment("production", fn -> assert rendered_blocks(production_page) =~ ~S(http:\/\/acme.test\/en\/work) end)
      in_environment("staging", fn -> assert rendered_blocks(staging_page) =~ ~S(http:\/\/acme.test\/en\/work) end)

      production = Registry.get_environment_by_key(context.site, "production")
      assert {:ok, _} = Registry.update_environment(production, %{domain: "www.acme.test"}, actor: :system)

      in_environment("production", fn ->
        assert rendered_blocks(production_page) =~ ~S(http:\/\/www.acme.test\/en\/work)
      end)

      in_environment("staging", fn ->
        assert rendered_blocks(staging_page) =~ ~S(http:\/\/www.acme.test\/en\/work)
      end)
    end
  end

  describe "when the identity changes, an entry using a shared module that shows it" do
    test "is rendered again", context do
      user = Brando.Factory.insert(:random_user)
      site = Registry.get_site(context.site.id)

      {:ok, shared} =
        Brando.Content.SharedLibrary.create_shared(:module, work_list_module("<p>{{ identity.name }}</p>"), :system)

      :ok = Brando.Content.SharedLibrary.set_enabled(site, :module, [shared.id])

      in_environment("production", fn ->
        page = module_page!(user, shared.id, :shared)
        {:ok, identity} = Brando.Sites.get_identity(%{matches: %{language: "en"}})
        refute rendered_blocks(page) =~ "Acme Renamed"

        {:ok, _} = Brando.Sites.update_identity(identity, %{name: "Acme Renamed"}, user)
        assert rendered_blocks(page) =~ "Acme Renamed"
      end)
    end
  end

  describe "with group authorization, when the live environment's domain changes" do
    setup do
      put_test_env(:authorization_mode, :groups)
      admin = Brando.Factory.insert(:random_user, role: :superuser, avatar: nil)
      {:ok, _} = Brando.Authorization.Migration.run()
      %{admin: admin}
    end

    test "another environment's entries are found and rendered there, whichever is selected", context do
      staging_page =
        in_environment("staging", fn ->
          page = json_ld_page!(context.admin)
          [block] = Brando.Repo.all(from(b in Page.Blocks, where: b.entry_id == ^page.id))
          module_id = Brando.Repo.get!(Brando.Content.Block, block.block_id).module_id
          {:ok, module_id: module_id, page: page}
        end)

      {:ok, module_id: module_id, page: page} = staging_page

      # Production has no module with that id
      in_environment("production", fn ->
        Brando.Repo.delete_all(from(m in Brando.Content.Module, where: m.id == ^module_id))
      end)

      assert {:ok, %{domain: "www.acme.test"}} = change_domain_as(context.admin, context.site, "www.acme.test")

      in_environment("staging", fn ->
        assert rendered_blocks(page) =~ ~S(http:\/\/www.acme.test\/en\/work)
      end)
    end

    test "a failure to queue the renders is logged and leaves the domain saved", context do
      page = in_environment("production", fn -> json_ld_page!(context.admin) end)

      # Staging's modules cannot be read
      Ecto.Adapters.SQL.query!(
        Brando.Repo.repo(),
        "ALTER TABLE tenant_acme_staging.content_modules RENAME TO content_modules_gone"
      )

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert {:ok, %{domain: "www.acme.test"}} = change_domain_as(context.admin, context.site, "www.acme.test")
        end)

      assert log =~ "tenant_acme_staging"
      assert Registry.get_environment_by_key(context.site, "production").domain == "www.acme.test"

      # The other environments are rendered all the same
      in_environment("production", fn -> assert rendered_blocks(page) =~ ~S(http:\/\/www.acme.test\/en\/work) end)
    end
  end

  describe "after a copy" do
    test "block JSON-LD stored on Staging and copied to Production names Production's host", context do
      in_environment("staging", &store_block_json_ld/0)

      source = Registry.get_environment_by_key(context.site, "staging")
      target = Registry.get_environment_by_key(context.site, "production")
      assert {:ok, _} = Brando.Environments.copy_environment(source, target, creator: :system)

      in_environment("production", fn -> assert_stored_json_ld_names("http://acme.test") end)
    end
  end

  describe "with no domain to use" do
    test "outside every site it is the endpoint's URL" do
      assert Brando.Utils.hostname() == Brando.endpoint().url()
    end

    test "a site whose environments have no domain uses the endpoint's URL" do
      {:ok, beta} = Registry.create_site(Map.merge(site_attrs(), %{name: "Beta", key: "beta"}))
      {:ok, _production} = Registry.create_environment(beta, %{name: "Production", key: "production", live: true})

      Tenant.with_prefix(Tenant.prefix("beta", "production"), fn ->
        assert Brando.Utils.hostname("/about") == Brando.endpoint().url() <> "/about"
      end)
    end

    test "in :none it is the endpoint's URL" do
      put_test_env(:tenancy_mode, :none)
      assert Brando.Utils.hostname() == Brando.endpoint().url()
    end
  end

  describe "in :single" do
    test "a process with no prefix names the live environment's domain, one with a prefix its own" do
      put_test_env(:tenancy_mode, :single)
      put_test_env(:site_key, "acme")
      Tenant.put_prefix(nil)

      assert Brando.Utils.hostname() == "http://acme.test"
      in_environment("staging", fn -> assert Brando.Utils.hostname() == "http://staging.acme.test" end)
    end
  end

  # og:url, the canonical, the `.md` alternate and every JSON-LD `@id` and URL
  defp assert_head_names(html, base_url) do
    {:ok, document} = Floki.parse_document(html)

    assert [og_url] = Floki.attribute(document, ~s(meta[property="og:url"]), "content")
    assert [canonical] = Floki.attribute(document, ~s(link[rel="canonical"]), "href")
    assert [markdown] = Floki.attribute(document, ~s(link[type="text/markdown"]), "href")

    [json] = document |> Floki.find(~s(script[type="application/ld+json"])) |> Enum.map(&Floki.children/1)
    graph = json |> Enum.join() |> Jason.decode!() |> Map.fetch!("@graph")
    urls = graph |> collect_urls() |> Enum.uniq()

    assert "#{base_url}/#identity" in urls
    assert "#{base_url}/#website" in urls
    assert "#{base_url}/#breadcrumb" in urls
    assert "#{base_url}/about" in urls

    for url <- [og_url, canonical, markdown | urls] do
      assert url == base_url or String.starts_with?(url, base_url <> "/"), "#{url} is not on #{base_url}"
    end
  end

  defp assert_one_page_url(html, url) do
    {:ok, document} = Floki.parse_document(html)

    assert Floki.attribute(document, ~s(meta[property="og:url"]), "content") == [url]
    assert Floki.attribute(document, ~s(link[rel="canonical"]), "href") == [url]

    graph = head_urls(html)
    page_urls = graph |> Enum.map(&(&1 |> URI.parse() |> Map.put(:fragment, nil) |> URI.to_string())) |> Enum.uniq()

    # The site's own nodes (#identity, #website) are on the origin
    assert page_urls -- [URI.parse(url) |> Map.put(:path, nil) |> URI.to_string() |> Kernel.<>("/")] == [url]
    assert (url <> "#webpage") in graph
    assert (url <> "#article") in graph
  end

  defp about_page! do
    user = Brando.Factory.insert(:random_user)

    {:ok, page} =
      Brando.Pages.create_page(
        %{title: "About", uri: "about", language: "en", template: "default.html", status: :published},
        user
      )

    page
  end

  defp head_urls(html) do
    {:ok, document} = Floki.parse_document(html)
    [json] = document |> Floki.find(~s(script[type="application/ld+json"])) |> Enum.map(&Floki.children/1)
    json |> Enum.join() |> Jason.decode!() |> Map.fetch!("@graph") |> collect_urls()
  end

  # What a page's render stores for a datasource block whose template emits
  # JSON-LD for its entries, through the Liquid filter and the HEEx component
  defp store_block_json_ld do
    page = Brando.Repo.get_by!(Page, uri: "index", language: :en)
    user = Brando.Factory.insert(:random_user)

    {:ok, work} =
      Brando.Pages.create_page(
        %{title: "Work", uri: "work", language: "en", template: "default.html", status: :published},
        user
      )

    {:ok, identifier} = Brando.Content.get_identifier(Page, work)

    block = %{
      module_id: 1,
      uid: "json-ld-block",
      vars: [],
      refs: [],
      table_rows: [],
      block_identifiers: [%{identifier_id: identifier.id, sequence: 0}]
    }

    module = %Brando.Content.Module{
      id: 1,
      datasource: true,
      datasource_type: :single,
      datasource_module: to_string(Chosen),
      datasource_query: "chosen"
    }

    liquid = %{module | type: :liquid, code: ~s({{ entries | json_ld: "CreativeWork", "page" }})}
    heex = %{module | type: :heex, code: ~S(<.json_ld entries={@entries} type="CreativeWork" />)}

    context =
      Brando.Villain.get_base_context()
      |> Liquex.Context.assign("url", Brando.Blueprint.URL.resolve(page))
      |> Liquex.Context.assign("language", "en")

    opts = %{context: context, parser_module: Brando.Villain.Parser}

    html =
      Brando.Villain.TemplateAdapter.Liquex.render_module(liquid, block, %{}, %{}, opts) <>
        Brando.Villain.TemplateAdapter.Heex.render_module(heex, block, %{}, %{}, opts)

    {1, _} =
      Brando.Repo.update_all(from(p in Page, where: p.id == ^page.id), set: [rendered_blocks: html])
  end

  # A published "work" page with a block of a module that lists it, and its
  # JSON-LD, through a datasource; rendered and stored
  defp json_ld_page!(user) do
    {:ok, module} = Brando.Content.create_module(work_list_module(), user)
    module_page!(user, module.id, :local)
  end

  defp work_list_module(code \\ ~s({{ entries | json_ld: "CreativeWork" }})) do
    Brando.Factory.params_for(:module,
      name: %{"en" => "Work list"},
      namespace: %{"en" => "Content"},
      help_text: %{"en" => "Help"},
      code: code,
      datasource: true,
      datasource_module: to_string(Chosen),
      datasource_type: :list,
      datasource_query: "work"
    )
  end

  defp module_page!(user, module_id, origin) do
    {:ok, page} =
      Brando.Pages.create_page(
        %{title: "Work", uri: "work", language: "en", template: "default.html", status: :published},
        user
      )

    block =
      %Brando.Content.Block{}
      |> Brando.Content.Block.recursive_block_changeset(
        %{
          "uid" => Brando.Utils.generate_uid(),
          "type" => "module",
          "module_id" => module_id,
          "module_origin" => to_string(origin),
          "creator_id" => user.id,
          "source" => to_string(Page.Blocks)
        },
        user
      )
      |> Brando.Repo.insert!()

    Brando.Repo.insert!(%Page.Blocks{entry_id: page.id, block_id: block.id, sequence: 0})
    {:ok, _} = Brando.Content.Blocks.render_entry(Page, page.id)
    page
  end

  defp rendered_blocks(page), do: Brando.Repo.get!(Page, page.id).rendered_blocks

  defp assert_stored_json_ld_names(base_url) do
    page = Brando.Repo.get_by!(Page, uri: "index", language: :en)
    {:ok, document} = Floki.parse_fragment(page.rendered_blocks)
    scripts = Floki.find(document, ~s(script[type="application/ld+json"]))
    assert length(scripts) == 2

    urls =
      Enum.flat_map(scripts, fn script ->
        script |> Floki.children() |> Enum.join() |> Jason.decode!() |> Map.delete("@context") |> collect_urls()
      end)

    assert "#{base_url}/en/work" in urls
    assert "#{base_url}/#website" in urls

    for url <- urls do
      assert url == base_url or String.starts_with?(url, base_url <> "/"), "#{url} is not on #{base_url}"
    end
  end

  # As the Environments screen saves it: in a transaction, with Production
  # selected and the admin's scope naming it
  defp change_domain_as(admin, site, domain) do
    scope = in_environment("production", fn -> Brando.Authorization.Scope.current(admin) end)
    assert scope.prefix == "tenant_acme_production"

    in_environment("production", fn -> in_scoped_transaction(scope, fn -> change_domain(admin, site, domain) end) end)
  end

  defp in_scoped_transaction(scope, fun),
    do: Brando.Authorization.Boundary.with_scope(scope, fn -> Brando.Repo.transaction(fun) end)

  defp change_domain(admin, site, domain) do
    production = Registry.get_environment_by_key(site, "production")

    case Registry.update_environment(production, %{domain: domain}, actor: admin) do
      {:ok, updated} -> updated
      {:error, reason} -> Brando.Repo.rollback(reason)
    end
  end

  # This node's registry cache with `cached` as the environment's domain, the
  # database with `stored`
  defp stale_registry_cache(environment, cached, stored) do
    query = from(e in Brando.Environments.Environment, where: e.id == ^environment.id)
    Brando.Repo.update_all(query, [set: [domain: cached]], prefix: "public")
    Tenant.Cache.warm()
    Brando.Repo.update_all(query, [set: [domain: stored]], prefix: "public")
  end

  defp set_live(site, key) do
    environment = Registry.get_environment_by_key(site, key)
    assert {:ok, %{live: true}} = Brando.Environments.set_live(environment, creator: :system)
  end

  defp collect_urls(map) when is_map(map), do: Enum.flat_map(map, fn {_key, value} -> collect_urls(value) end)
  defp collect_urls(list) when is_list(list), do: Enum.flat_map(list, &collect_urls/1)
  defp collect_urls("http" <> _ = url), do: [url]
  defp collect_urls(_value), do: []

  defp request(host, path \\ "/") do
    Tenant.put_prefix(nil)

    conn =
      :get
      |> Plug.Test.conn("https://#{host}#{path}")
      |> Map.put(:host, host)
      |> Brando.SiteURLTest.Router.call(Brando.SiteURLTest.Router.init([]))

    assert conn.status == 200
    conn
  after
    Tenant.put_prefix(nil)
  end

  # The build requests its own origin (127.0.0.1 here), with the signed context header
  defp build(site, environment, root, ssg_module \\ RootOnly, file \\ "index.html") do
    output_path = Path.join(root, "output-#{environment.key}")
    static_path = Path.join(root, "static")
    File.mkdir_p!(static_path)

    fetcher = fn url, opts ->
      uri = URI.parse(url)
      assert uri.host == "127.0.0.1"

      conn =
        Enum.reduce(opts[:headers] || [], Plug.Test.conn(:get, url), fn {name, value}, conn ->
          Plug.Conn.put_req_header(conn, name, value)
        end)

      conn = Brando.SiteURLTest.Router.call(conn, Brando.SiteURLTest.Router.init([]))
      {:ok, %{status: conn.status, body: conn.resp_body, headers: []}}
    end

    assert {:ok, _result} =
             Brando.SSG.build(site, environment,
               base_url: "http://127.0.0.1:4999",
               output_path: output_path,
               static_path: static_path,
               media_path: Path.join(root, "no-media"),
               ssg_module: ssg_module,
               # Its router answers the pages only
               site_files: false,
               fetcher: fetcher
             )

    Tenant.put_prefix(nil)
    File.read!(Path.join(output_path, file))
  end

  defp in_environment(key, fun), do: Tenant.with_prefix(Tenant.prefix("acme", key), fun)

  defp restore_cache({key, nil}), do: Brando.Cache.del(key)
  defp restore_cache({key, value}), do: Brando.Cache.put(key, value, :infinite)

  defp environments do
    [
      %{name: "Production", key: "production", live: true, domain: "acme.test"},
      %{name: "Staging", key: "staging", live: false, domain: "staging.acme.test"},
      %{name: "Lab", key: "lab", live: false}
    ]
  end

  defp site_attrs do
    %{
      name: "Acme",
      key: "acme",
      languages: ["en"],
      default_language: "en",
      status: :active,
      delivery_mode: :dynamic
    }
  end
end

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
  end

  def assign_language(conn, _opts), do: Plug.Conn.assign(conn, :language, "en")
end

defmodule Brando.SiteURLTest do
  # The absolute URLs a site's pages carry name the host of the environment
  # rendered, not the endpoint's (the admin's)
  use Brando.ConnCase, async: false

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

  defmodule RootOnly do
    import Brando.SSG

    urls :pages do
      ["/"]
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

    test "alternate links given as paths get the environment's host" do
      in_environment("staging", fn ->
        conn =
          Phoenix.ConnTest.build_conn(:get, "/en/about")
          |> Plug.Conn.assign(:language, "en")
          |> Brando.Plug.HTML.put_hreflang(en: "/en/about", no: "/no/om")

        assert conn.private.brando_hreflangs == [
                 {"en", "http://staging.acme.test/en/about"},
                 {:en, "http://staging.acme.test/en/about"},
                 {:no, "http://staging.acme.test/no/om"}
               ]
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
    {:ok, module} =
      Brando.Content.create_module(
        Brando.Factory.params_for(:module,
          name: %{"en" => "Work list"},
          namespace: %{"en" => "Content"},
          help_text: %{"en" => "Help"},
          code: ~s({{ entries | json_ld: "CreativeWork" }}),
          datasource: true,
          datasource_module: to_string(Chosen),
          datasource_type: :list,
          datasource_query: "work"
        ),
        user
      )

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
          "module_id" => module.id,
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

  defp set_live(site, key) do
    environment = Registry.get_environment_by_key(site, key)
    assert {:ok, %{live: true}} = Brando.Environments.set_live(environment, creator: :system)
  end

  defp collect_urls(map) when is_map(map), do: Enum.flat_map(map, fn {_key, value} -> collect_urls(value) end)
  defp collect_urls(list) when is_list(list), do: Enum.flat_map(list, &collect_urls/1)
  defp collect_urls("http" <> _ = url), do: [url]
  defp collect_urls(_value), do: []

  defp request(host) do
    Tenant.put_prefix(nil)

    conn =
      :get
      |> Plug.Test.conn("https://#{host}/")
      |> Map.put(:host, host)
      |> Brando.SiteURLTest.Router.call(Brando.SiteURLTest.Router.init([]))

    assert conn.status == 200
    conn
  after
    Tenant.put_prefix(nil)
  end

  # The build requests its own origin (127.0.0.1 here), with the signed context header
  defp build(site, environment, root) do
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
               ssg_module: RootOnly,
               fetcher: fetcher
             )

    Tenant.put_prefix(nil)
    File.read!(Path.join(output_path, "index.html"))
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

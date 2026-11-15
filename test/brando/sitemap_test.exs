defmodule BrandoIntegrationWeb.Sitemap do
  import Brando.Sitemap
  alias Brando.Pages

  sitemap "pages" do
    Pages.list_pages(
      %{filter: %{has_url: true}, status: :published, select: [:title, :uri, :updated_at]},
      :stream
    )
    |> Stream.map(fn _entry ->
      page_url = Brando.Utils.hostname("index")

      lastmod = ~N[2023-08-10 10:00:00]

      url(%{
        priority: 0.7,
        changefreq: :weekly,
        loc: page_url,
        lastmod: lastmod
      })
    end)
  end
end

defmodule Brando.SitemapTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase
  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Sitemap
  alias Sitemapper.URL

  test "url/1 percent-encodes loc once" do
    assert Sitemap.url(%{loc: "http://localhost/news/Some post"}).loc ==
             "http://localhost/news/Some%20post"

    assert Sitemap.url(%{loc: "http://localhost/news/Some%20post"}).loc ==
             "http://localhost/news/Some%20post"

    assert Sitemap.url(%{loc: "http://localhost/illustrators/eno-_janelle?x=1"}).loc ==
             "http://localhost/illustrators/eno-_janelle?x=1"
  end

  test "check_lastmod/1" do
    url = %URL{lastmod: ~N[2023-12-20 14:00:00], loc: "/"}
    checked_url = Sitemap.check_lastmod(url)
    assert DateTime.to_iso8601(checked_url.lastmod) == "2023-12-20T15:00:00+01:00"
    url = %URL{lastmod: checked_url.lastmod, loc: "/"}
    checked_url = Sitemap.check_lastmod(url)
    assert DateTime.to_iso8601(checked_url.lastmod) == "2023-12-20T15:00:00+01:00"
  end

  test "reject_without_loc/2 drops entries without a URL and says how many" do
    previous = Logger.level()
    Logger.configure(level: :warning)
    on_exit(fn -> Logger.configure(level: previous) end)

    urls = [%URL{loc: "http://localhost/a"}, %URL{loc: nil}, %URL{loc: ""}]

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        assert [%URL{loc: "http://localhost/a"}] = urls |> Sitemap.reject_without_loc("pages") |> Enum.to_list()
      end)

    assert log =~ "Sitemap pages: skipped 2 entries without a URL"
  end

  test "sitemap/1" do
    usr = Factory.insert(:random_user)

    {:ok, _p1} =
      Pages.create_page(
        Factory.params_for(:page, title: "Title English", language: :en),
        usr
      )

    assert Sitemap.exists?()
    assert BrandoIntegrationWeb.Sitemap.__info__(:functions) == [__sitemap_for_pages__: 0]
    assert {:ok, _} = Sitemap.generate_sitemap(gzip: false)

    sitemap_index_path = Path.join([Brando.config(:media_path), "sitemaps", "sitemap.xml"])
    sitemap_index = File.read!(sitemap_index_path)

    assert sitemap_index =~ "<loc>http://localhost/sitemaps/sitemap-00001.xml</loc>"

    sitemap_path = Path.join([Brando.config(:media_path), "sitemaps", "sitemap-00001.xml"])
    sitemap = File.read!(sitemap_path)

    assert sitemap =~
             "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<urlset xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xsi:schemaLocation=\"http://www.sitemaps.org/schemas/sitemap/0.9 http://www.sitemaps.org/schemas/sitemap/0.9/sitemap.xsd\" xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n<url>\n  <loc>http://localhost/index</loc>\n  <lastmod>2023-08-10T12:00:00+02:00</lastmod>\n  <changefreq>weekly</changefreq>\n  <priority>0.7</priority>\n</url>\n</urlset>\n"
  end

  describe "in multi-site mode" do
    defmodule Migrator do
      @behaviour Brando.Environments.Migrator

      @impl true
      def migrate(_site, _environment), do: {:ok, []}
    end

    @tag :tmp_dir
    test "the index and the entries name the site's host, not the endpoint's", %{tmp_dir: dir} do
      put_test_env(:media_path, Path.join(dir, "media"))
      put_test_env(:sites_path, Path.join(dir, "sites"))
      put_test_env(:tenant_migrator, Migrator)
      put_test_env(:tenant_structure_cloner, Brando.TenantCloners)
      put_test_env(:environment_schema_cloner, Brando.TenantCloners)
      put_test_env(:tenancy_mode, :multi)
      Brando.Tenant.put_prefix(nil)
      Brando.Tenant.Cache.clear()
      cached = for key <- ~w(identity seo navigation)a, do: {key, Brando.Cache.get(key)}

      on_exit(fn ->
        Brando.Tenant.put_prefix(nil)
        Brando.Tenant.Cache.clear()
        Brando.TenantCaches.clear(["tenant_acme_production"])

        for {key, value} <- cached,
            do: if(value, do: Brando.Cache.put(key, value, :infinite), else: Brando.Cache.del(key))
      end)

      creator = Factory.insert(:random_user, role: :superuser, avatar: nil)

      {:ok, _site} =
        Brando.Tenant.Setup.create_site(
          %{name: "Acme", key: "acme", languages: ["en"], default_language: "en", status: :active},
          creator,
          environments: [%{name: "Production", key: "production", live: true, domain: "acme.test"}]
        )

      Brando.Tenant.with_prefix("tenant_acme_production", fn ->
        assert {:ok, _} = Sitemap.generate_sitemap(gzip: false)
      end)

      sitemaps = Path.join([dir, "media", "acme", "sitemaps"])
      assert File.read!(Path.join(sitemaps, "sitemap.xml")) =~ "<loc>http://acme.test/sitemaps/sitemap-00001.xml</loc>"
      assert File.read!(Path.join(sitemaps, "sitemap-00001.xml")) =~ "<loc>http://acme.test/index</loc>"
    end
  end

  @tag :tmp_dir
  test "exists? finds a sitemap module that isn't loaded yet, as in a mix task", %{tmp_dir: dir} do
    # A module on the code path but not loaded, as an application's modules
    # are when `mix brando.doctor` starts
    module = :"Elixir.Brando.SitemapTest.Unloaded#{System.unique_integer([:positive])}"
    [{^module, beam}] = Code.compile_string("defmodule #{inspect(module)} do\nend")
    File.write!(Path.join(dir, "#{module}.beam"), beam)
    :code.purge(module)
    :code.delete(module)
    :code.purge(module)
    true = :code.add_patha(String.to_charlist(dir))
    on_exit(fn -> :code.del_path(String.to_charlist(dir)) end)
    refute :erlang.module_loaded(module)

    assert Sitemap.exists?(module)
    refute Sitemap.exists?(:"Elixir.Brando.SitemapTest.NoSuchModule")
  end
end

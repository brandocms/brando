defmodule Brando.Plug.TenantTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.SSG.Context
  alias Brando.Tenant
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry

  @site_attrs %{
    name: "Acme",
    key: "acme",
    languages: ["en"],
    default_language: "en",
    status: :active,
    delivery_mode: :dynamic
  }

  setup do
    put_test_env(:tenancy_mode, :multi)
    Tenant.put_prefix(nil)
    Cache.clear()

    on_exit(fn ->
      Tenant.put_prefix(nil)
      Cache.clear()
    end)

    {:ok, site} = Registry.create_site(@site_attrs)

    {:ok, environment} =
      Registry.create_environment(
        site,
        %{
          name: "Production",
          key: "production",
          live: true,
          domain: "www.acme.test"
        },
        actor: :system
      )

    %{site: site, environment: environment}
  end

  test "resolves a domain from cache and assigns frontend tenant context", context do
    conn =
      :get
      |> Plug.Test.conn("https://WWW.ACME.TEST/")
      |> Map.put(:host, "WWW.ACME.TEST")
      |> Brando.Plug.Tenant.call([])

    assert conn.assigns.current_site.id == context.site.id
    assert conn.assigns.current_environment.id == context.environment.id
    assert conn.assigns.tenant_prefix == "tenant_acme_production"
    assert Tenant.current_prefix() == "tenant_acme_production"
    refute conn.private[:brando_ssg_build]
  end

  test "single-site mode falls back to the configured live environment", context do
    put_test_env(:tenancy_mode, :single)
    put_test_env(:site_key, "acme")

    conn =
      :get
      |> Plug.Test.conn("https://unmapped.test/")
      |> Map.put(:host, "unmapped.test")
      |> Brando.Plug.Tenant.call([])

    assert conn.assigns.current_site.id == context.site.id
    assert conn.assigns.current_environment.id == context.environment.id
    assert Tenant.current_prefix() == "tenant_acme_production"
  end

  test "unknown multi-site hosts clear stale process context" do
    Tenant.put_prefix("tenant_acme_production")

    conn =
      :get
      |> Plug.Test.conn("https://unknown.test/")
      |> Map.put(:host, "unknown.test")
      |> Brando.Plug.Tenant.call([])

    refute conn.assigns[:current_site]
    assert conn.halted
    assert conn.status == 404
    assert Tenant.current_prefix() == nil
  end

  test "a signed SSG header resolves a domainless working environment", context do
    {:ok, staging} =
      Registry.create_environment(context.site, %{
        name: "Staging",
        key: "staging",
        live: false
      })

    token = Context.sign(context.site, staging)

    conn =
      :get
      |> Plug.Test.conn("https://unknown.test/")
      |> Plug.Conn.put_req_header(Context.header(), token)
      |> Map.put(:host, "unknown.test")
      |> Brando.Plug.Tenant.call([])

    assert conn.assigns.current_site.id == context.site.id
    assert conn.assigns.current_environment.id == staging.id
    assert conn.assigns.tenant_prefix == "tenant_acme_staging"
    assert conn.private.brando_ssg_build
    refute conn.halted
  end

  describe "robots.txt for a static build's request" do
    setup context do
      {:ok, staging} =
        Registry.create_environment(
          context.site,
          %{name: "Staging", key: "staging", live: false, domain: "staging.acme.test"},
          actor: :system
        )

      prefix = "tenant_acme_staging"
      key = {:tenant, prefix, :seo}
      cached = Cachex.get!(:cache, key)
      Cachex.put(:cache, key, %{"en" => %Brando.Sites.SEO{robots: nil}})

      on_exit(fn ->
        if cached, do: Cachex.put(:cache, key, cached), else: Cachex.del(:cache, key)
      end)

      %{staging: staging}
    end

    defp robots(conn, headers) do
      conn =
        Enum.reduce(headers, conn, fn {name, value}, conn -> Plug.Conn.put_req_header(conn, name, value) end)
        |> Brando.Plug.Tenant.call([])
        |> Plug.Conn.assign(:language, "en")
        |> BrandoWeb.SEOController.robots(%{})

      conn.resp_body
    end

    defp build_conn_on(host), do: :get |> Plug.Test.conn("http://#{host}/robots.txt") |> Map.put(:host, host)

    test "answers as the site's public host, naming the sitemap the build says it has", context do
      token = Context.sign(context.site, context.staging)

      body = robots(build_conn_on("localhost"), [{Context.header(), token}, {Context.sitemap_header(), "1"}])

      # The admin answers on the endpoint's host, not on the site's
      assert body =~ "Disallow:\n"
      refute body =~ "/admin/"
      assert body =~ ~r{Sitemap: https?://www\.acme\.test(:\d+)?/sitemaps/sitemap\.xml\.gz}
      refute body =~ "staging.acme.test"

      body = robots(build_conn_on("localhost"), [{Context.header(), token}, {Context.sitemap_header(), "0"}])
      refute body =~ "Sitemap:"
    end

    test "ignores the sitemap header on a request that is not a build's", _context do
      body = robots(build_conn_on("staging.acme.test"), [{Context.sitemap_header(), "1"}])
      refute body =~ "Sitemap:"
    end
  end

  test "a tampered SSG header cannot bypass unknown-host rejection", context do
    token = Context.sign(context.site, context.environment) <> "tampered"

    conn =
      :get
      |> Plug.Test.conn("https://unknown.test/")
      |> Plug.Conn.put_req_header(Context.header(), token)
      |> Map.put(:host, "unknown.test")
      |> Brando.Plug.Tenant.call([])

    assert conn.halted
    assert conn.status == 404
  end

  test "suspended sites are no longer served by their domains", context do
    assert {:ok, _site} = Registry.update_site(context.site, %{status: :suspended})

    conn =
      :get
      |> Plug.Test.conn("https://www.acme.test/")
      |> Map.put(:host, "www.acme.test")
      |> Brando.Plug.Tenant.call([])

    assert conn.halted
    assert conn.status == 404
    refute conn.assigns[:current_site]
    assert Tenant.current_prefix() == nil
  end

  test "none mode preserves the public-schema behavior" do
    put_test_env(:tenancy_mode, :none)
    Tenant.put_prefix("tenant_acme_production")

    conn =
      :get
      |> Plug.Test.conn("https://www.acme.test/")
      |> Map.put(:host, "www.acme.test")
      |> Brando.Plug.Tenant.call([])

    refute conn.assigns[:current_site]
    assert Tenant.current_prefix() == nil
  end
end

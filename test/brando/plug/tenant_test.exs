defmodule Brando.Plug.TenantTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

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
      Registry.create_environment(site, %{
        name: "Production",
        key: "production",
        live: true,
        domain: "www.acme.test"
      })

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

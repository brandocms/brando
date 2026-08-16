defmodule Brando.Plug.AdminTenantTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Plug.AdminTenant
  alias Brando.Tenant
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry

  setup %{conn: conn} do
    put_test_env(:tenancy_mode, :multi)
    Cache.clear()

    on_exit(fn ->
      Tenant.put_prefix(nil)
      Cache.clear()
    end)

    {:ok, site} =
      Registry.create_site(%{
        name: "Acme",
        key: "acme",
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :dynamic
      })

    {:ok, production} =
      Registry.create_environment(site, %{
        name: "Production",
        key: "production",
        live: true
      })

    {:ok, preview} =
      Registry.create_environment(site, %{
        name: "Preview",
        key: "preview",
        live: false
      })

    conn =
      conn
      |> init_test_session(%{
        "brando_site_key" => "acme",
        "brando_environment_key" => "preview"
      })
      |> Plug.Conn.assign(:current_user, Brando.Factory.insert(:random_user, role: :superuser))

    %{conn: conn, site: site, production: production, preview: preview}
  end

  test "does not restore an unassigned site for a regular user", context do
    user = Brando.Factory.insert(:random_user, role: :admin)
    conn = Plug.Conn.assign(context.conn, :current_user, user)

    conn = AdminTenant.call(conn, [])

    refute conn.assigns[:current_site]
    assert Tenant.current_prefix() == nil
  end

  test "restores the signed-session environment for controller requests", context do
    conn = AdminTenant.call(context.conn, [])

    assert conn.assigns.current_site.id == context.site.id
    assert conn.assigns.current_environment.id == context.preview.id
    assert Tenant.current_prefix() == "tenant_acme_preview"
  end

  test "clears stale process context when tenancy is disabled", context do
    Tenant.put_prefix("tenant_acme_preview")
    put_test_env(:tenancy_mode, :none)

    conn = AdminTenant.call(context.conn, [])

    refute conn.assigns[:current_site]
    assert Tenant.current_prefix() == nil
  end
end

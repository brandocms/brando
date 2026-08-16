defmodule BrandoAdmin.EnvironmentControllerTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

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

    %{conn: init_test_session(conn, %{}), site: site, production: production, preview: preview}
  end

  test "stores a valid site and environment selection", context do
    conn =
      BrandoAdmin.EnvironmentController.update(context.conn, %{
        "site_key" => "acme",
        "environment_key" => "preview",
        "return_to" => "/admin/pages"
      })

    assert get_session(conn, "brando_site_key") == "acme"
    assert get_session(conn, "brando_environment_key") == "preview"
    assert redirected_to(conn) == "/admin/pages"
  end

  test "falls back to live and rejects external return locations", context do
    conn =
      BrandoAdmin.EnvironmentController.update(context.conn, %{
        "site_key" => "acme",
        "environment_key" => "missing",
        "return_to" => "https://attacker.test/"
      })

    assert get_session(conn, "brando_environment_key") == "production"
    assert redirected_to(conn) == "/admin"
  end

  test "rejects paths which merely begin with the admin prefix", context do
    conn =
      BrandoAdmin.EnvironmentController.update(context.conn, %{
        "site_key" => "acme",
        "environment_key" => "preview",
        "return_to" => "/administrator"
      })

    assert redirected_to(conn) == "/admin"
  end
end

defmodule BrandoAdmin.EnvironmentControllerTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Tenant
  alias Brando.Tenant.Access
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

    superuser = Brando.Factory.insert(:random_user, role: :superuser)

    conn =
      conn
      |> init_test_session(%{})
      |> Plug.Conn.assign(:current_user, superuser)

    %{conn: conn, site: site, production: production, preview: preview}
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

  test "rejects a site selection the current user cannot access", context do
    editor = Brando.Factory.insert(:random_user, role: :editor)
    conn = Plug.Conn.assign(context.conn, :current_user, editor)

    conn =
      BrandoAdmin.EnvironmentController.update(conn, %{
        "site_key" => "acme",
        "environment_key" => "preview"
      })

    refute get_session(conn, "brando_site_key")
    refute get_session(conn, "brando_environment_key")
    assert redirected_to(conn) == "/admin"

    assert {:ok, _assignment} = Access.grant(editor, context.site, :editor)

    authorized_conn =
      context.conn
      |> Plug.Conn.assign(:current_user, editor)
      |> BrandoAdmin.EnvironmentController.update(%{
        "site_key" => "acme",
        "environment_key" => "preview"
      })

    assert get_session(authorized_conn, "brando_site_key") == "acme"
  end
end

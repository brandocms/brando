defmodule BrandoAdmin.UtilsSitemapLiveTest do
  # "Generate sitemap" fills the site's sitemap, which every environment
  # serves, so it reads the live environment and says so when another is
  # selected
  use Brando.LiveCase

  alias Brando.Tenant

  @prefixes ~w(tenant_acme_production tenant_acme_staging)

  defmodule Migrator do
    @behaviour Brando.Environments.Migrator

    @impl true
    def migrate(_site, _environment), do: {:ok, []}
  end

  setup %{conn: conn, current_user: user} do
    root = Path.join(System.tmp_dir!(), "brando-utils-sitemap-#{System.unique_integer([:positive])}")

    put_test_env(:media_path, Path.join(root, "media"))
    put_test_env(:sites_path, Path.join(root, "sites"))
    put_test_env(:tenant_migrator, Migrator)
    put_test_env(:tenant_structure_cloner, Brando.TenantCloners)
    put_test_env(:environment_schema_cloner, Brando.TenantCloners)
    put_test_env(:tenancy_mode, :multi)
    Tenant.put_prefix(nil)
    Tenant.Cache.clear()

    on_exit(fn ->
      File.rm_rf(root)
      Tenant.put_prefix(nil)
      Tenant.Cache.clear()
      Brando.TenantCaches.clear(@prefixes)
    end)

    {:ok, _site} =
      Tenant.Setup.create_site(
        %{name: "Acme", key: "acme", languages: ["en"], default_language: "en", status: :active},
        user,
        environments: [
          %{name: "Production", key: "production", live: true, domain: "acme.test"},
          %{name: "Staging", key: "staging", live: false, domain: "staging.acme.test"}
        ]
      )

    Brando.endpoint().subscribe("user:#{user.id}")
    %{conn: Plug.Conn.put_session(conn, "brando_site_key", "acme")}
  end

  test "with Staging selected, says it generated from the live environment", %{conn: conn} do
    {:ok, view, _html} = live(Plug.Conn.put_session(conn, "brando_environment_key", "staging"), "/admin/config/utils")
    view |> element("button", "Generate sitemap") |> render_click()

    assert_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{payload: message}}
    assert message == "Generated the sitemap from Production, the live environment."
  end

  test "with the live environment selected, says only that it generated", %{conn: conn} do
    {:ok, view, _html} =
      live(Plug.Conn.put_session(conn, "brando_environment_key", "production"), "/admin/config/utils")

    view |> element("button", "Generate sitemap") |> render_click()

    assert_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{payload: "Generated sitemap."}}
  end
end

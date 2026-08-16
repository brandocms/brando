defmodule BrandoAdmin.Sites.SiteLiveTest do
  use Brando.LiveCase

  alias Brando.Environments.Schema
  alias Brando.Tenant.Access
  alias Brando.Tenant.Registry

  defmodule Migrator do
    @behaviour Brando.Environments.Migrator

    @impl true
    def migrate(_site, _environment), do: {:ok, [20_260_816_000_001]}
  end

  defmodule SchemaCloner do
    @behaviour Brando.Environments.SchemaCloner

    @impl true
    def clone_schema(_source_prefix, target_prefix), do: Schema.create(target_prefix)
  end

  defmodule Seeder do
    @behaviour Brando.Tenant.Seeder

    @impl true
    def seed(_site, _environment, _creator), do: :ok
  end

  setup do
    root = Path.join(System.tmp_dir!(), "brando-site-live-#{System.unique_integer([:positive])}")

    put_test_env(:tenancy_mode, :multi)
    put_test_env(:tenant_migrator, Migrator)
    put_test_env(:environment_schema_cloner, SchemaCloner)
    put_test_env(:tenant_seeder, Seeder)
    put_test_env(:media_path, Path.join(root, "media"))
    put_test_env(:sites_path, Path.join(root, "sites"))
    Brando.Tenant.Cache.clear()

    on_exit(fn ->
      File.rm_rf(root)
      Brando.Tenant.put_prefix(nil)
      Brando.Tenant.Cache.clear()
    end)

    {:ok, site} =
      Registry.create_site(%{
        name: "Existing Site",
        key: "existing-site-dashboard",
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :dynamic
      })

    {:ok, _environment} =
      Registry.create_environment(site, %{
        name: "Production",
        key: "production",
        live: true,
        domain: "existing.dashboard.test"
      })

    editor =
      Brando.Factory.insert(:random_user,
        role: :editor,
        config: %Brando.Users.UserConfig{}
      )

    %{editor: editor, site: Registry.get_site(site.id)}
  end

  test "superusers provision sites and manage per-site assignments", %{conn: conn, editor: editor} do
    {:ok, view, html} = live(conn, "/admin/sites")

    assert html =~ "Existing Site"

    view
    |> form("#create-site-form",
      site: %{
        name: "New Client",
        key: "new-client-dashboard",
        languages: "en,no",
        default_language: "en",
        delivery_mode: "dynamic"
      }
    )
    |> render_submit()

    created = Registry.get_site_by_key("new-client-dashboard")
    assert created
    assert Enum.map(created.environments, & &1.key) |> Enum.sort() == ["production", "staging"]
    assert has_element?(view, "#site-#{created.id}", "New Client")

    view
    |> form("#grant-site-#{created.id}",
      assignment: %{site_id: created.id, user_id: editor.id, role: "admin"}
    )
    |> render_submit()

    assert Access.role_for(editor, created) == :admin
    assert has_element?(view, "#site-#{created.id}", editor.email)

    view
    |> element("#site-#{created.id} button[phx-click=revoke][phx-value-user-id=\"#{editor.id}\"]")
    |> render_click()

    refute Access.can_access?(editor, created)
  end

  test "site lifecycle actions immediately update status", %{conn: conn, site: site} do
    {:ok, view, _html} = live(conn, "/admin/sites")

    view
    |> element("#site-#{site.id} button", "Suspend")
    |> render_click()

    assert Registry.get_site(site.id).status == :suspended
    assert has_element?(view, "#site-#{site.id}", "suspended")

    view
    |> element("#site-#{site.id} button", "Archive")
    |> render_click()

    archived = Registry.get_site(site.id)
    assert archived.status == :archived
    assert archived.archived_at

    view
    |> element("#site-#{site.id} button", "Permanently delete")
    |> render_click()

    assert Registry.get_site(site.id)
  end

  test "non-superusers are redirected", %{editor: editor, site: site} do
    assert {:ok, _assignment} = Access.grant(editor, site, :admin)
    conn = log_in_user(Phoenix.ConnTest.build_conn(), editor)

    assert {:error, {:redirect, %{to: "/admin"}}} = live(conn, "/admin/sites")
  end
end

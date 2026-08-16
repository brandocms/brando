defmodule BrandoAdmin.Content.SharedLibraryLiveTest do
  use Brando.LiveCase

  alias Brando.Content.SharedLibrary
  alias Brando.Tenant.Access
  alias Brando.Tenant.Registry

  @prefix "tenant_shared-library-live_preview"

  setup %{current_user: current_user} do
    put_test_env(:tenancy_mode, :multi)
    Brando.Tenant.put_prefix(nil)
    SharedLibrary.Cache.clear()

    on_exit(fn ->
      Brando.Tenant.put_prefix(nil)
      SharedLibrary.Cache.clear()
    end)

    {:ok, site} =
      Registry.create_site(%{
        name: "Library Site",
        key: "shared-library-live",
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :dynamic
      })

    {:ok, _environment} =
      Registry.create_environment(site, %{
        name: "Preview",
        key: "preview",
        live: true
      })

    Ecto.Adapters.SQL.query!(BrandoIntegration.Repo, ~s|CREATE SCHEMA "#{@prefix}"|)

    for table <- ~w(content_modules content_vars content_refs content_containers content_palettes content_blocks) do
      Ecto.Adapters.SQL.query!(
        BrandoIntegration.Repo,
        ~s|CREATE TABLE "#{@prefix}"."#{table}" (LIKE public."#{table}" INCLUDING ALL)|
      )
    end

    {:ok, shared_module} =
      SharedLibrary.create_shared(
        :module,
        %{
          name: %{"en" => "Shared hero"},
          namespace: %{"en" => "general"},
          help_text: %{"en" => "Help"},
          class: "hero",
          code: "<section>Hero</section>"
        },
        current_user
      )

    %{site: site, shared_module: shared_module}
  end

  test "superusers manage access and create entries", %{
    conn: conn,
    site: site,
    shared_module: shared_module
  } do
    {:ok, view, html} = live(conn, "/admin/config/content/shared_library")

    assert html =~ "Shared content library"
    assert html =~ "Shared hero"
    assert has_element?(view, "#access-module")

    view
    |> form("#access-module", access: %{kind: "module", ids: [shared_module.id]})
    |> render_submit()

    assert SharedLibrary.enabled?(site, :module, shared_module.id)

    view
    |> element("#shared-module-#{shared_module.id} button[phx-click=customize]")
    |> render_click()

    assert %{source_module_id: source_id} =
             SharedLibrary.get(:module, shared_module.id, :shared, site, @prefix)

    assert source_id == shared_module.id
    assert has_element?(view, "#shared-module-#{shared_module.id}", "Edit customization")

    view
    |> form("#create-shared-container",
      entry: %{
        kind: "container",
        name: "Shared wrapper",
        namespace: "general",
        type: "liquid",
        code: "<main>{{ content }}</main>"
      }
    )
    |> render_submit()

    assert has_element?(view, "#shared-library-container", "Shared wrapper")
  end

  test "the full module editor opens shared entries from public", %{
    conn: conn,
    shared_module: shared_module
  } do
    assert {:ok, _view, html} =
             live(conn, "/admin/config/content/shared_library/modules/update/#{shared_module.id}")

    assert html =~ "Shared module library"
    assert html =~ "Changelog note"
  end

  test "site administrators can customize enabled entries but cannot mutate the global library", %{
    site: site,
    shared_module: shared_module
  } do
    site_admin =
      Brando.Factory.insert(:random_user,
        role: :editor,
        config: %Brando.Users.UserConfig{}
      )

    assert :ok = SharedLibrary.enable(site, :module, shared_module.id)
    assert {:ok, _assignment} = Access.grant(site_admin, site, :admin)
    conn = log_in_user(Phoenix.ConnTest.build_conn(), site_admin)

    assert {:ok, view, html} = live(conn, "/admin/config/content/shared_library")
    assert html =~ "Site library"
    refute has_element?(view, "#create-shared-module")

    view
    |> element("#shared-module-#{shared_module.id} button[phx-click=customize]")
    |> render_click()

    assert %{source_module_id: source_id} =
             SharedLibrary.get(:module, shared_module.id, :shared, site, @prefix)

    assert source_id == shared_module.id

    render_click(view, "delete", %{"kind" => "module", "id" => shared_module.id})
    assert SharedLibrary.get_shared(:module, shared_module.id)
  end

  test "users without site access are redirected" do
    editor =
      Brando.Factory.insert(:random_user,
        role: :editor,
        config: %Brando.Users.UserConfig{}
      )

    conn = log_in_user(Phoenix.ConnTest.build_conn(), editor)

    assert {:error, {:redirect, %{to: "/admin"}}} =
             live(conn, "/admin/config/content/shared_library")
  end
end

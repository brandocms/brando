defmodule BrandoAdmin.AuthorizationToolsLiveTest do
  use Brando.LiveCase
  alias Brando.Authorization.{Configuration, Group, Groups, Migration, Scope}

  setup do
    put_test_env(:authorization_mode, :legacy)
    put_test_env(:tenancy_mode, :none)
  end

  test "superusers can report, backfill and review groups before cutover", %{conn: conn} do
    {:ok, view, _} = live(conn, "/admin/config/utils")
    assert has_element?(view, "#authorization-tools", "Legacy roles active")
    assert has_element?(view, "button[phx-click=authorization_backfill][disabled]")
    view |> element("button", "Run migration report") |> render_click()
    render_async(view)
    assert has_element?(view, "#authorization-migration-report", "Application rules")
    assert Repo.all(Group) == []
    view |> element("button", "Prepare groups") |> render_click()
    render_async(view)
    assert has_element?(view, "[role=status]", "Groups prepared")
    refute Brando.Authorization.enabled?()
    assert length(Repo.all(Group)) == 4
    {:ok, groups, _} = live(conn, "/admin/groups")
    assert has_element?(groups, ".authorization-legacy-notice", "Legacy roles are still active")
    assert has_element?(groups, "#navigation a[href='/admin/groups']", "Permissions")
    assert has_element?(groups, "button", "New group")
  end

  test "ordinary legacy administrators cannot see tools, forge their events, or enter groups", %{conn: conn} do
    admin = Factory.insert(:random_user, role: :admin, config: %Brando.Users.UserConfig{})
    conn = log_in_user(conn, admin)
    {:ok, view, _} = live(conn, "/admin/config/utils")
    refute has_element?(view, "#authorization-tools")
    refute has_element?(view, "#navigation a[href='/admin/groups']")
    render_click(view, "authorization_backfill")
    assert_redirect(view, "/admin/access-denied")
    assert Repo.all(Group) == []
    assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = live(conn, "/admin/groups")
  end

  test "file import is reviewed before applying and export is private to the live response", %{
    conn: conn,
    current_user: user
  } do
    {:ok, view, _} = live(conn, "/admin/config/utils")

    json =
      Jason.encode!(%{
        format: "brando.authorization",
        version: 1,
        scope: "standalone",
        groups: [
          %{
            key: "campaign",
            name: "Campaign editors",
            description: "Seasonal campaigns",
            preset: nil,
            permissions: ["brando.admin.access", "brando.pages.read"]
          }
        ]
      })

    upload =
      file_input(view, "#authorization-import-form", :authorization_config, [
        %{name: "reviewed.json", content: json, type: "application/json"}
      ])

    assert render_upload(upload, "reviewed.json") =~ "reviewed.json"
    view |> form("#authorization-import-form") |> render_submit()
    assert has_element?(view, "#authorization-import-preview", "Campaign editors")
    assert Repo.all(Group) == []
    view |> element("button", "Apply configuration") |> render_click()
    assert has_element?(view, "[role=status]", "1 groups created")
    assert {:ok, [group]} = Groups.list(Scope.standalone(user))
    assert group.name == "Campaign editors"
    view |> element("button", "Prepare export") |> render_click()
    assert has_element?(view, "a[download='brando-groups-standalone.json'][href^='data:application/json;base64,']")
  end

  test "invalid uploads display a useful error and never write groups", %{conn: conn} do
    {:ok, view, _} = live(conn, "/admin/config/utils")

    upload =
      file_input(view, "#authorization-import-form", :authorization_config, [
        %{name: "invalid.json", content: "not json", type: "application/json"}
      ])

    render_upload(upload, "invalid.json")
    view |> form("#authorization-import-form") |> render_submit()
    assert has_element?(view, "[role=alert]", "not valid JSON")
    refute has_element?(view, "#authorization-import-preview")
    assert Repo.all(Group) == []
  end

  test "group mode utilities permissions alone do not grant migration or import access", %{
    conn: conn,
    current_user: owner
  } do
    put_test_env(:authorization_mode, :groups)
    {:ok, _} = Migration.run()
    admin = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})

    {:ok, group} =
      Groups.create(Scope.standalone(owner), %{name: "Utilities manager"}, [
        "brando.admin.access",
        "brando.utilities.read",
        "brando.utilities.update"
      ])

    {:ok, :ok} = Groups.add_member(Scope.standalone(owner), group.id, admin.id)
    {:ok, view, _} = live(log_in_user(conn, admin), "/admin/config/utils")
    refute has_element?(view, "#authorization-tools")
    render_click(view, "authorization_export")
    assert_redirect(view, "/admin/access-denied")
    assert {:error, :forbidden} = Configuration.export(Scope.standalone(admin))
  end
end

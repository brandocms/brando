defmodule BrandoAdmin.Users.GroupsLiveTest do
  use Brando.LiveCase
  alias Brando.Authorization.{Boundary, Groups, Migration, Scope}

  setup %{current_user: user} do
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, :none)
    Boundary.put_scope(nil)
    {:ok, _} = Migration.run()
    on_exit(fn -> Boundary.put_scope(nil) end)
    %{scope: Scope.standalone(user)}
  end

  test "renders scoped groups and saves a reviewed custom group", %{conn: conn, scope: scope} do
    {:ok, view, _html} = live(conn, "/admin/groups")
    assert has_element?(view, "h1", "Permissions")
    assert has_element?(view, "#navigation dd a[href='/admin/groups']", "Permissions")
    refute has_element?(view, "#navigation dt a[href='/admin/groups']")
    view |> element("button", "New group") |> render_click()

    view
    |> form("#group-permissions",
      group: %{name: "News team", description: "Weekly publishing"},
      permissions: %{"brando.admin.access" => "true", "brando.pages.read" => "true"}
    )
    |> render_change()

    view |> form("#group-permissions") |> render_submit()
    assert has_element?(view, ".authorization-review", "2 permissions added")
    view |> element("button", "Confirm & save") |> render_click()
    assert has_element?(view, "[role=status]", "Group saved")
    assert {:ok, groups} = Groups.list(scope)
    assert Enum.find(groups, &(&1.name == "News team"))
  end

  test "direct routes deny a user without backend access", %{conn: conn} do
    user = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
    conn = log_in_user(conn, user)
    assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = live(conn, "/admin/groups")
    assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = live(conn, "/admin/pages")
  end

  test "removing access redirects an already mounted group editor", %{conn: conn, scope: scope} do
    user = Factory.insert(:random_user, role: :editor, config: %Brando.Users.UserConfig{})
    {:ok, group} = Groups.create(scope, %{name: "Access reviewer"}, ["brando.admin.access", "brando.groups.read"])
    {:ok, :ok} = Groups.add_member(scope, group.id, user.id)
    {:ok, view, _} = live(log_in_user(conn, user), "/admin/groups")
    {:ok, :ok} = Groups.remove_member(scope, group.id, user.id)
    assert_redirect(view, "/admin/access-denied")
  end

  test "membership edits preserve the unsaved permission draft", %{conn: conn, scope: scope, current_user: user} do
    {:ok, group} = Groups.create(scope, %{name: "Original"}, ["brando.admin.access"])
    {:ok, view, _} = live(conn, "/admin/groups")
    render_click(view, "select", %{"id" => to_string(group.id)})

    view
    |> form("#group-permissions",
      group: %{name: "Unsaved name", description: "Draft"},
      permissions: %{"brando.admin.access" => "true", "brando.pages.read" => "true"}
    )
    |> render_change()

    render_click(view, "tab", %{"tab" => "members"})
    render_click(view, "show_add_member")
    view |> element("button[phx-value-user_id='#{user.id}']") |> render_click()
    render_click(view, "tab", %{"tab" => "permissions"})
    assert has_element?(view, "input[name='group[name]'][value='Unsaved name']")
    assert has_element?(view, "input[name='permissions[brando.pages.read]'][checked]")
    assert {:ok, %{name: "Original"}} = Groups.get(scope, group.id)
    render_click(view, "tab", %{"tab" => "members"})
    render_click(view, "new")
    assert has_element?(view, "#group-permissions")
  end

  test "stale saves preserve another administrator's changes and explain recovery", %{conn: conn, scope: scope} do
    {:ok, group} = Groups.create(scope, %{name: "Original"}, ["brando.admin.access"])
    {:ok, view, _} = live(conn, "/admin/groups")
    render_click(view, "select", %{"id" => to_string(group.id)})

    {:ok, _} =
      Groups.update(
        scope,
        group.id,
        %{name: "Concurrent edit"},
        ["brando.admin.access", "brando.pages.read"],
        group.lock_version
      )

    view |> form("#group-permissions", group: %{name: "Stale overwrite"}) |> render_change()
    view |> form("#group-permissions") |> render_submit()
    render_click(view, "save")
    assert has_element?(view, "[role=alert]", "changed while you were editing")
    assert {:ok, %{name: "Concurrent edit"}} = Groups.get(scope, group.id)
  end

  test "an empty browser description is pristine, and selecting the same group keeps a draft", %{conn: conn, scope: scope} do
    {:ok, group} = Groups.create(scope, %{name: "Reviewers"}, ["brando.admin.access"])
    {:ok, view, _} = live(conn, "/admin/groups")
    render_click(view, "select", %{"id" => to_string(group.id)})

    view
    |> form("#group-permissions",
      group: %{name: "Reviewers", description: ""},
      permissions: %{"brando.admin.access" => "true"}
    )
    |> render_change()

    assert has_element?(view, "#authorization-workspace[data-dirty=false]")
    assert has_element?(view, "button[form=group-permissions][disabled]")
    view |> form("#group-permissions", group: %{name: "Draft name"}) |> render_change()
    render_click(view, "select", %{"id" => to_string(group.id)})
    assert has_element?(view, "input[name='group[name]'][value='Draft name']")
  end

  test "filtering and editing visible grants keeps hidden grants", %{conn: conn, scope: scope} do
    {:ok, group} =
      Groups.create(scope, %{name: "Reviewers"}, ["brando.admin.access", "brando.pages.read", "brando.pages.update"])

    {:ok, view, _} = live(conn, "/admin/groups")
    render_click(view, "select", %{"id" => to_string(group.id)})
    view |> form("#group-permissions", search: "Pages") |> render_change()
    assert has_element?(view, "input[name='permissions[brando.pages.read]'][checked]")
    refute has_element?(view, "input[name='permissions[brando.admin.access]']")
    render_change(view, "change", %{"search" => "Pages", "permissions" => %{"brando.pages.read" => "true"}})
    view |> form("#group-permissions") |> render_submit()
    assert has_element?(view, ".authorization-review", "1 permission removed")
    assert has_element?(view, ".authorization-review", "Pages · Edit")
    render_click(view, "save")
    {:ok, saved} = Groups.get(scope, group.id)
    assert Enum.sort(Enum.map(saved.grants, & &1.permission_key)) == ["brando.admin.access", "brando.pages.read"]
  end

  test "review validates and uses final submitted values", %{conn: conn, scope: scope} do
    {:ok, view, _} = live(conn, "/admin/groups")
    render_click(view, "new")
    render_submit(view, "review", %{"group" => %{"name" => "   "}})
    refute has_element?(view, ".authorization-review")
    assert has_element?(view, "[role=alert]", "Enter a group name")
    # No change event precedes this submit: debounced input must still be saved.
    render_submit(view, "review", %{
      "group" => %{"name" => "Final name"},
      "permissions" => %{"brando.admin.access" => "true"}
    })

    assert has_element?(view, ".authorization-review", "Final name")
    render_click(view, "save")
    {:ok, groups} = Groups.list(scope)
    assert Enum.any?(groups, &(&1.name == "Final name"))
  end

  test "members already in a group are excluded from its picker and activity has names", %{
    conn: conn,
    scope: scope,
    current_user: user
  } do
    {:ok, group} = Groups.create(scope, %{name: "Reviewers"}, ["brando.admin.access"])
    {:ok, :ok} = Groups.add_member(scope, group.id, user.id)
    {:ok, view, _} = live(conn, "/admin/groups")
    render_click(view, "select", %{"id" => to_string(group.id)})
    render_click(view, "tab", %{"tab" => "members"})
    render_click(view, "show_add_member")
    refute has_element?(view, "button[phx-value-user_id='#{user.id}']")
    render_click(view, "tab", %{"tab" => "activity"})
    assert has_element?(view, ".authorization-activity", user.name)
  end

  test "permission search recognizes the action labels shown to people", %{conn: conn} do
    {:ok, view, _} = live(conn, "/admin/groups")
    view |> form("#group-permissions", search: "Edit") |> render_change()
    assert has_element?(view, "input[name='permissions[brando.pages.update]']")
    refute has_element?(view, "input[name='permissions[brando.pages.delete]']")
  end

  test "installation groups are discoverable through grants without the Superuser preset", %{
    conn: conn,
    scope: scope,
    current_user: admin
  } do
    user = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})
    keys = ["brando.admin.access", "brando.groups.read"]
    {:ok, workspace} = Groups.create(scope, %{name: "Workspace reviewer"}, keys)
    {:ok, installation} = Groups.create(Scope.installation(admin), %{name: "Installation reviewer"}, keys)
    {:ok, :ok} = Groups.add_member(scope, workspace.id, user.id)
    {:ok, :ok} = Groups.add_member(Scope.installation(admin), installation.id, user.id)
    {:ok, view, _} = live(log_in_user(conn, user), "/admin/groups")
    assert has_element?(view, "a[href='/admin/groups?scope=installation']", "Installation groups")
    refute has_element?(view, "#authorization-review-button")
  end

  test "row selection moves from mixed to all to none without changing other rows or details", %{conn: conn, scope: scope} do
    {:ok, group} = Groups.create(scope, %{name: "Row reviewers"}, ["brando.admin.access", "brando.pages.read"])
    {:ok, view, _} = live(conn, "/admin/groups")
    render_click(view, "select", %{"id" => to_string(group.id)})
    view |> form("#group-permissions", group: %{name: "Unsaved row name"}) |> render_change()
    row = "button[phx-value-resource='brando.pages']"
    assert has_element?(view, row <> "[aria-checked=mixed]")
    view |> element(row) |> render_click()
    assert has_element?(view, row <> "[aria-checked=true]")

    for action <- ~w(read create update delete publish) do
      assert has_element?(view, "input[name='permissions[brando.pages.#{action}]'][checked]")
    end

    view |> element(row) |> render_click()
    assert has_element?(view, row <> "[aria-checked=false]")
    refute has_element?(view, "input[name^='permissions[brando.pages.'][checked]")
    assert has_element?(view, "input[name='permissions[brando.admin.access]'][checked]")
    assert has_element?(view, "input[name='group[name]'][value='Unsaved row name']")
  end

  test "row selection is limited to search results and keeps hidden grants", %{conn: conn, scope: scope} do
    {:ok, group} = Groups.create(scope, %{name: "Filtered row"}, ["brando.admin.access", "brando.pages.publish"])
    {:ok, view, _} = live(conn, "/admin/groups")
    render_click(view, "select", %{"id" => to_string(group.id)})
    view |> form("#group-permissions", search: "View") |> render_change()
    view |> element("button[phx-value-resource='brando.pages']") |> render_click()
    view |> form("#group-permissions", search: "") |> render_change()
    assert has_element?(view, "input[name='permissions[brando.pages.read]'][checked]")
    assert has_element?(view, "input[name='permissions[brando.pages.publish]'][checked]")
    assert has_element?(view, "input[name='permissions[brando.admin.access]'][checked]")
    refute has_element?(view, "input[name='permissions[brando.pages.create]'][checked]")
  end

  test "a delegated group editor can bulk-grant only permissions they hold", %{conn: conn, scope: scope} do
    user = Factory.insert(:random_user, role: :user, config: %Brando.Users.UserConfig{})

    {:ok, manager} =
      Groups.create(scope, %{name: "Delegated manager"}, [
        "brando.admin.access",
        "brando.groups.read",
        "brando.groups.update",
        "brando.pages.read"
      ])

    {:ok, :ok} = Groups.add_member(scope, manager.id, user.id)
    {:ok, target} = Groups.create(scope, %{name: "Limited row"}, [])
    {:ok, view, _} = live(log_in_user(conn, user), "/admin/groups")
    render_click(view, "select", %{"id" => to_string(target.id)})
    view |> element("button[phx-value-resource='brando.pages']") |> render_click()
    assert has_element?(view, "input[name='permissions[brando.pages.read]'][checked]")
    assert has_element?(view, "input[name='permissions[brando.pages.publish]'][disabled]")
    refute has_element?(view, "input[name='permissions[brando.pages.publish]'][checked]")
    # A forged event for a wholly locked resource also grants nothing.
    render_click(view, "toggle_resource", %{"resource" => "brando.users"})
    view |> form("#group-permissions") |> render_submit()
    render_click(view, "save")
    {:ok, saved} = Groups.get(scope, target.id)
    assert Enum.map(saved.grants, & &1.permission_key) == ["brando.pages.read"]
  end
end

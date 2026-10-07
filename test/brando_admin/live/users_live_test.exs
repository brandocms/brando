defmodule BrandoAdmin.UsersLiveTest do
  # The user directory: who is listed and how, creating and updating a user,
  # and deleting one by handing their content to someone else. This was
  # e2e/playwright/tests/users/users.spec.js; all of it is server-rendered.
  # The spec branched on the authorization mode, so both modes run here.
  use Brando.LiveCase

  alias Brando.Users.User

  @email "coverage-editor@brandocms.com"

  # As the E2E fixture: the signed-in admin has an avatar and recorded
  # activity.
  defp directory_admin(user) do
    name = "users-live-#{System.unique_integer([:positive])}.jpg"
    relative = Path.join("images", name)
    path = Path.join(Brando.config(:media_path), relative)
    File.mkdir_p!(Path.dirname(path))
    File.cp!(Path.expand("../../fixtures/sample.jpg", __DIR__), path)
    on_exit(fn -> File.rm(path) end)

    avatar =
      Repo.insert!(%Brando.Images.Image{
        path: relative,
        status: :processed,
        width: 292,
        height: 173,
        config_target: "image:Brando.Users.User:avatar",
        formats: [:jpg],
        sizes: %{"thumb" => relative, "small" => relative}
      })

    user
    |> Ecto.Changeset.change(
      avatar_id: avatar.id,
      last_seen: ~N[2026-09-07 12:34:00],
      last_login: ~N[2026-09-06 08:15:00]
    )
    |> Repo.update!()
  end

  defp listing(conn) do
    {:ok, view, _html} = live(conn, "/admin/users")
    await_selector(view, ".list-row")
    view
  end

  defp row(user), do: "#list-row-#{user.id}"
  defp row_text(view, user), do: view |> element(row(user)) |> render() |> Floki.parse_fragment!() |> Floki.text()

  defp attr(view, selector, name) do
    view |> render() |> Floki.parse_document!() |> Floki.find(selector) |> Floki.attribute(name)
  end

  defp filter_by_name(view, query) do
    view
    |> element("form[id$='-name']")
    |> render_change(%{"q" => query, "filter" => "name"})
  end

  defp save_user(view, params) do
    view |> form("#user_form_form", %{"user" => params}) |> render_submit()
    assert_redirect(view, "/admin/users", 3_000)
  end

  defp await_gone(view, selector, deadline \\ System.monotonic_time(:millisecond) + 2_000) do
    cond do
      not has_element?(view, selector) -> :ok
      System.monotonic_time(:millisecond) > deadline -> flunk("#{selector} is still listed")
      true -> Process.sleep(20) && await_gone(view, selector, deadline)
    end
  end

  defp the_directory(%{conn: conn, current_user: admin}, groups?) do
    admin = directory_admin(admin)
    view = listing(conn)

    # The admin's row: a served avatar, the role and recorded activity.
    [src] = attr(view, "#{row(admin)} .user-avatar img", "src")
    media_file = Path.join(Brando.config(:media_path), String.replace_prefix(URI.parse(src).path, "/media/", ""))
    assert File.exists?(media_file), "the avatar's src (#{src}) does not point at its file"
    assert view |> element("#{row(admin)} .user-role") |> render() =~ ~r/superuser/i
    assert attr(view, "#{row(admin)} .user-last-seen time", "datetime") == ["2026-09-07T12:34:00Z"]
    assert attr(view, "#{row(admin)} .user-last-login time", "datetime") == ["2026-09-06T08:15:00Z"]
    assert view |> element(".user-directory-columns") |> render() =~ if(groups?, do: "Legacy role", else: "Role")

    # Create
    {form, _html} = live_form(conn, "/admin/users/create", "user_form")
    assert has_element?(form, "input[type=radio][name='user[language]'][value=en]")
    role = if groups?, do: %{}, else: %{"role" => "editor"}

    if groups?,
      do: refute(has_element?(form, "input[type=radio][name='user[role]'][value=editor]")),
      else: assert(has_element?(form, "input[type=radio][name='user[role]'][value=editor]"))

    save_user(
      form,
      Map.merge(%{"name" => "Coverage Editor", "email" => @email, "password" => "brandocms", "language" => "en"}, role)
    )

    created = Repo.get_by!(User, email: @email)
    view = listing(conn)
    assert row_text(view, created) =~ "Coverage Editor"

    assert view |> element("#{row(created)} .user-role") |> render() =~
             if(groups?, do: ~r/user/i, else: ~r/editor/i)

    assert view |> element("#{row(created)} .user-last-login") |> render() =~ "Not recorded"

    filter_by_name(view, "Coverage Editor")
    assert view |> render() |> Floki.parse_document!() |> Floki.find(".content-list .list-row") |> length() == 1
    assert row_text(view, created) =~ @email
    filter_by_name(view, "")

    # Update
    assert has_element?(view, "#{row(created)} a[href='/admin/users/update/#{created.id}']", "Coverage Editor")
    {form, _html} = live_form(conn, "/admin/users/update/#{created.id}", "user_form")
    save_user(form, %{"name" => "Updated Coverage Editor"})

    view = listing(conn)
    assert row_text(view, created) =~ "Updated Coverage Editor"

    # Delete, handing the user's content to the admin
    view |> element("#entry-dropdown-default-#{created.id} button", "Delete user") |> render_click()
    modal = "#transfer-content-modal"
    assert view |> element(modal) |> render() =~ "This user has no content to transfer."
    assert has_element?(view, "#{modal} button[phx-click='confirm_transfer_delete'][disabled]")
    view |> element("#{modal} .transfer-user-trigger", "Select user...") |> render_click()
    view |> element("#{modal} button", admin.name) |> render_click()
    view |> element("#{modal} button[phx-click='confirm_transfer_delete']", "Transfer & Delete") |> render_click()

    # The listing refreshes from a broadcast after the delete.
    await_gone(view, row(created))
    assert Repo.get!(User, created.id).deleted_at
  end

  test "legacy roles: the directory lists, creates, updates and deletes a user", context do
    the_directory(context, false)
  end

  test "group permissions: the directory lists, creates, updates and deletes a user", context do
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, :none)
    Brando.Authorization.Boundary.put_scope(nil)
    {:ok, _} = Brando.Authorization.Migration.run()
    on_exit(fn -> Brando.Authorization.Boundary.put_scope(nil) end)

    the_directory(context, true)
  end
end

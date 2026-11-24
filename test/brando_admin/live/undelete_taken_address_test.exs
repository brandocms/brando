defmodule BrandoAdmin.UndeleteTakenAddressTest do
  # Undelete in the listing's trash on an entry whose address was taken
  # while it was there (#3941): it comes back with a suffix, a draft as
  # well as a published entry. An address it still can't have, or a row
  # gone since the list was drawn, shows the error toast; the view stays up.
  use Brando.LiveCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.Pages
  alias Brando.Pages.Page
  alias Brando.RestoreTest.Project

  setup %{current_user: user} do
    put_test_env(:tenancy_mode, :none)
    Brando.endpoint().subscribe("user:#{user.id}")
    :ok
  end

  test "a draft page comes back a draft, at its address with a suffix", c do
    draft = trashed_page!(c.current_user, %{uri: "about", status: :draft})
    page!(c.current_user, %{uri: "about"})

    view = open_trash(c.conn, "/admin/pages")
    undelete(view, draft)

    assert {_message, :success} = toast()
    assert %Page{deleted_at: nil, status: :draft, uri: "about-1"} = Repo.get!(Page, draft.id)
    assert render(view)
  end

  test "a draft of another type comes back a draft, at its address with a suffix", c do
    draft = project!(c.current_user, %{slug: "about", status: :draft})
    {:ok, draft} = Brando.Repo.soft_delete(draft)
    project!(c.current_user, %{slug: "about"})

    view = open_trash(c.conn, "/admin/restore/projects")
    undelete(view, draft)

    assert {_message, :success} = toast()
    assert %Project{deleted_at: nil, status: :draft, slug: "about-1"} = Repo.get!(Project, draft.id)
    assert render(view)
  end

  test "an address taken all the same shows the error toast and leaves the page in the trash", c do
    draft = trashed_page!(c.current_user, %{uri: "about", status: :draft})
    # Trashed without freeing its address: the check passes over the trash, the index does not
    held = page!(c.current_user, %{uri: "about"})
    Brando.Repo.soft_delete_all(from(p in Page, where: p.id == ^held.id))

    view = open_trash(c.conn, "/admin/pages")
    undelete(view, draft)

    assert {_message, :error} = toast()
    assert Repo.get!(Page, draft.id).deleted_at
    assert render(view)
  end

  test "a page deleted for good since the list was drawn shows the error toast", c do
    page = trashed_page!(c.current_user, %{uri: "about"})
    view = open_trash(c.conn, "/admin/pages")
    assert :ok = Brando.SoftDelete.Query.purge_entry(Page, page.id, page.deleted_at, c.current_user)

    undelete(view, page)

    assert {_message, :error} = toast()
    assert render(view)
  end

  test "a page restored since the list was drawn is not reported restored again", c do
    page = trashed_page!(c.current_user, %{uri: "about"})
    view = open_trash(c.conn, "/admin/pages")
    {:ok, _} = Brando.Authorization.Boundary.restore(c.current_user, Repo.get!(Page, page.id))

    undelete(view, page)

    assert {_message, :error} = toast()
    assert render(view)
  end

  defp open_trash(conn, path) do
    {:ok, view, _html} = live(conn, path <> "?status=deleted")
    view
  end

  defp undelete(view, entry), do: render_click(view, "undelete_entry", %{"id" => to_string(entry.id)})

  defp toast do
    assert_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{payload: message} = payload}
    {message, payload[:level]}
  end

  defp trashed_page!(user, attrs) do
    page = page!(user, attrs)
    {:ok, page} = Pages.delete_page(page.id, user)
    page
  end

  defp page!(user, attrs) do
    params = Map.merge(%{title: "Page", language: "en", template: "default.html", status: :published}, attrs)
    {:ok, page} = Pages.create_page(params, user)
    page
  end

  defp project!(user, attrs) do
    {:ok, project} = Brando.RestoreTest.create_project(Map.merge(%{title: "Project", status: :published}, attrs), user)
    project
  end
end

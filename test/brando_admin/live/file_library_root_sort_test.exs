defmodule BrandoAdmin.FileLibraryRootSortTest do
  @moduledoc """
  "Sort by use" at the Files library's root, as at the Videos library's
  (#3649). The root is the default file config's upload folder, so it lists
  the files with no folder and those in the root's own folder record: the
  sort takes both, and Undo puts them back with no folder.
  """
  # Grouped, one at a time: it takes the authorization lock (Brando.Authorization.Groups.lock!/0),
  # which a test's sandbox transaction holds until the test ends
  use Brando.LiveCase, async: true, group: :shared_locks

  import Ecto.Query

  alias Brando.Content.Block
  alias Brando.Files.File, as: MediaFile
  alias Brando.Media.Folder
  alias Brando.Pages.Page
  alias Brando.Repo
  alias BrandoAdmin.Images.FolderBrowser

  @sort "button[phx-click=sweep_open]"

  defp show(files, title \\ "About us") do
    page = Factory.insert(:page, title: title, uri: Brando.Utils.slugify(title), language: "en")
    Brando.Content.create_identifier(Page, page)

    block =
      Repo.insert!(%Block{type: :module, source: "Elixir.Brando.Pages.Page.Blocks", uid: Brando.Utils.generate_uid()})

    Repo.insert!(%Page.Blocks{entry_id: page.id, block_id: block.id, sequence: 0})
    Enum.each(files, &Factory.insert(:ref, block_id: block.id, file_id: &1.id))
  end

  defp file(folder_id, name) do
    Repo.insert!(%MediaFile{
      filename: name,
      filesize: 100,
      mime_type: "application/pdf",
      config_target: "default",
      folder_id: folder_id
    })
  end

  defp folder_of(%MediaFile{id: id}), do: Repo.one(from f in MediaFile, where: f.id == ^id, select: f.folder_id)

  test "Sort by use at the root sorts the root's loose files, and Undo puts them back", %{conn: conn} do
    root = FolderBrowser.folder_id_for("files/default")
    terms = FolderBrowser.folder_id_for("files/default/terms")
    loose = file(nil, "price-list.pdf")
    in_root = file(root, "menu.pdf")
    filed = file(terms, "terms.pdf")
    unused = file(nil, "old-terms.pdf")
    show([loose, in_root, filed])

    {:ok, view, _html} = live(conn, "/admin/assets/files")
    assert has_element?(view, @sort)

    view |> element(@sort) |> render_click()
    assert has_element?(view, "#file-sweep .media-sweep-entry", "About us")
    assert has_element?(view, "#file-sweep .media-sweep-tile[title='price-list.pdf']")
    assert has_element?(view, "#file-sweep .media-sweep-tile[title='menu.pdf']")
    refute has_element?(view, "#file-sweep .media-sweep-tile[title='terms.pdf']")

    view |> form("#file-sweep-form") |> render_submit()
    assert Repo.get!(Folder, folder_of(loose)).path == "default/pages/about-us"
    assert folder_of(in_root) == folder_of(loose)
    assert folder_of(filed) == terms
    assert folder_of(unused) == nil
    # Only the unused one is left at the root
    assert has_element?(view, ".image-picker-main-actions span", "1 file")

    view |> element("button[phx-click=sweep_undo]") |> render_click()
    assert folder_of(loose) == nil
    assert folder_of(in_root) == nil
    assert folder_of(filed) == terms
    assert has_element?(view, ".image-picker-main-actions span", "3 files")
  end

  # The page falls back to the root, but the listing filters on the folder
  # named: a sort would move root files it isn't showing.
  test "a folder filter that doesn't resolve offers no sort", %{conn: conn} do
    file(nil, "loose.pdf")
    hidden = Brando.Media.Folders.hidden_folder_id("uploads")
    gone = FolderBrowser.folder_id_for("files/default/gone")
    Repo.delete!(Repo.get!(Folder, gone))

    for folder_id <- [hidden, gone, FolderBrowser.folder_id_for("videos/default/clips")] do
      {:ok, view, _html} = live(conn, "/admin/assets/files?filter:folder_id=#{folder_id}")
      refute has_element?(view, @sort)
    end

    {:ok, view, _html} = live(conn, "/admin/assets/files?filter:folder_id=root")
    assert has_element?(view, @sort)
  end

  test "a root with no loose files, and All folders, offer no sort", %{conn: conn} do
    file(FolderBrowser.folder_id_for("files/default/terms"), "terms.pdf")

    {:ok, view, _html} = live(conn, "/admin/assets/files")
    refute has_element?(view, @sort)

    file(nil, "loose.pdf")
    {:ok, view, _html} = live(conn, "/admin/assets/files?filter:folder_id=all")
    refute has_element?(view, @sort)
  end
end

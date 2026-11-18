defmodule BrandoAdmin.AssetLibrarySearchFolderTest do
  @moduledoc """
  The media libraries keep the search and the folder in view in URL
  parameters of their own: the Videos library's "Title or source" and the
  Images library's "Path" search in `filter:path`, a stored folder in
  `filter:folder_id`, and a folder known only by its assets' paths in
  `filter:folder_path`. A search that names a folder searches; it doesn't
  open that folder. A link in the old shape, which opened a folder known by
  its path as `filter:path`, still opens it.
  """
  # Grouped, one at a time: a media list inserts the folders of the upload
  # paths (BrandoAdmin.Images.FolderBrowser), unique by path, which
  # concurrent transactions would wait on
  use Brando.LiveCase, async: true, group: :shared_locks

  import Brando.Test.Users

  alias Brando.Content.Block
  alias Brando.Pages.Page
  alias Brando.Repo
  alias BrandoAdmin.Images.FolderBrowser

  @videos "/admin/assets/videos"
  @images "/admin/assets/images"
  @heading ".image-picker-main-header h3"
  @sort "button[phx-click=sweep_open]"
  @video_search "#listing-filter-form-Elixir\\.Brando\\.Videos\\.Video-path"
  @image_search "#listing-filter-form-Elixir\\.Brando\\.Images\\.Image-path"

  defp show(videos, title) do
    page = Factory.insert(:page, title: title, uri: Brando.Utils.slugify(title), language: "en")
    Brando.Content.create_identifier(Page, page)

    block =
      Repo.insert!(%Block{type: :module, source: "Elixir.Brando.Pages.Page.Blocks", uid: Brando.Utils.generate_uid()})

    Repo.insert!(%Page.Blocks{entry_id: page.id, block_id: block.id, sequence: 0})
    Enum.each(videos, &Factory.insert(:ref, block_id: block.id, video_id: &1.id))
  end

  defp reader(conn), do: log_in_as(conn, permissions: ~w(brando.images.read))

  defp search(view, form, query), do: view |> form(form, %{q: query}) |> render_change()

  defp heading(view),
    do: view |> element(@heading) |> render() |> Floki.parse_fragment!() |> Floki.text() |> String.trim()

  describe "the Videos library" do
    setup do
      folder_id = FolderBrowser.folder_id_for("videos/default/Intervjuer")
      filed = Factory.insert(:video, folder_id: folder_id, title: "Filed clip")
      loose = Factory.insert(:video, title: "Intervjuer i Bergen")
      {:ok, folder_id: folder_id, filed: filed, loose: loose}
    end

    test "a search that names a folder keeps the heading and the folder", %{conn: conn} = c do
      {:ok, view, _html} = live(conn, @videos <> "?filter:path=Intervjuer")

      assert heading(view) == "Library root"
      assert has_element?(view, "#list-row-#{c.loose.id}")
      refute has_element?(view, "#list-row-#{c.filed.id}")
      # The folder stays one to open, not the one in view
      assert has_element?(view, ".image-picker-folders button", "Intervjuer")
      refute has_element?(view, ".image-picker-path .path-link", "Intervjuer")
    end

    test "typing a search that names a folder at the library's first view", %{conn: conn} = c do
      {:ok, view, _html} = live(conn, @videos)

      search(view, @video_search, "Intervjuer")
      assert_patch(view, @videos <> "?filter:path=Intervjuer")
      assert heading(view) == "Library root"
      assert has_element?(view, "#list-row-#{c.loose.id}")
    end

    test "a search inside a folder stays in it, and clearing it lists the folder again", %{conn: conn} = c do
      other = Factory.insert(:video, folder_id: c.folder_id, title: "Another clip")
      {:ok, view, _html} = live(conn, @videos <> "?filter:folder_id=#{c.folder_id}")

      search(view, @video_search, "Filed")
      assert_patch(view, @videos <> "?filter:folder_id=#{c.folder_id}&filter:path=Filed")
      assert heading(view) == "Intervjuer"
      assert has_element?(view, "#list-row-#{c.filed.id}")
      refute has_element?(view, "#list-row-#{other.id}")
      refute has_element?(view, "#list-row-#{c.loose.id}")

      search(view, @video_search, "")
      assert_patch(view, @videos <> "?filter:folder_id=#{c.folder_id}")
      assert heading(view) == "Intervjuer"
      assert has_element?(view, "#list-row-#{c.filed.id}")
      assert has_element?(view, "#list-row-#{other.id}")
    end

    test "a search names no folder for Sort by use: the root's sort sorts the root", %{conn: conn} = c do
      show([c.loose], "Root page")
      show([c.filed], "Folder page")

      {:ok, view, _html} = live(conn, @videos <> "?filter:path=Intervjuer")
      assert has_element?(view, @sort)

      view |> element(@sort) |> render_click()
      assert has_element?(view, "#video-sweep .media-sweep-entry", "Root page")
      refute has_element?(view, "#video-sweep .media-sweep-entry", "Folder page")
    end

    test "a search inside a folder keeps that folder's sort", %{conn: conn} = c do
      show([c.loose], "Root page")
      show([c.filed], "Folder page")

      {:ok, view, _html} = live(conn, @videos <> "?filter:folder_id=#{c.folder_id}&filter:path=Filed")
      view |> element(@sort) |> render_click()
      assert has_element?(view, "#video-sweep .media-sweep-entry", "Folder page")
      refute has_element?(view, "#video-sweep .media-sweep-entry", "Root page")
    end

    test "a folder link in the old shape still opens the folder, with no search", %{conn: conn} = c do
      # The first render patches to the new shape, which a browser follows
      old_link = @videos <> "?filter:path=videos/default/Intervjuer"
      conn_get = get(conn, @videos, %{"filter:path" => "videos/default/Intervjuer"})
      # A folder stored since opens by its id, as the folder list opens it
      assert redirected_to(conn_get) == @videos <> "?filter%3Afolder_id=#{c.folder_id}"

      {:ok, view, html} = live(conn, old_link)
      assert heading(view) == "Intervjuer"
      assert has_element?(view, "#list-row-#{c.filed.id}")
      refute has_element?(view, "#list-row-#{c.loose.id}")
      refute html =~ "Title or source:"
    end

    test "a search link in the old shape still searches", %{conn: conn} = c do
      {:ok, view, html} = live(conn, @videos <> "?filter:path=Bergen")

      assert html =~ "Title or source: Bergen"
      assert heading(view) == "Library root"
      assert has_element?(view, "#list-row-#{c.loose.id}")
      refute has_element?(view, "#list-row-#{c.filed.id}")
    end
  end

  describe "the Images library" do
    setup do
      put_test_env(:authorization_mode, :groups)
      put_test_env(:tenancy_mode, :none)

      # Uploaded before folders were stored: in a folder by its path only
      legacy = Factory.insert(:image, status: :processed, path: "images/legacy/pics/a.jpg", folder_id: nil)
      loose = Factory.insert(:image, status: :processed, path: "images/legacy-notes.jpg", folder_id: nil)
      {:ok, legacy: legacy, loose: loose}
    end

    test "a search that names a folder keeps the heading and the folder", %{conn: conn} do
      {conn, _user} = reader(conn)
      {:ok, view, _html} = live(conn, @images <> "?filter:folder_id=root")

      search(view, @image_search, "legacy")
      assert_patch(view, @images <> "?filter:folder_id=root&filter:path=legacy")
      assert heading(view) == "Root folder"

      {:ok, view, _html} = live(conn, @images <> "?filter:path=legacy")
      assert heading(view) == "Root folder"
      refute has_element?(view, ".image-picker-path .path-link", "legacy")
    end

    # A reader: the folder isn't stored for them, so it opens by its path
    test "a folder known by its path opens as such, and a search in it stays there", %{conn: conn} = c do
      {conn, _user} = reader(conn)
      {:ok, view, _html} = live(conn, @images <> "?filter:folder_id=root")

      render_click(view, "assets_go_folder", %{"folder" => "legacy/pics"})
      assert_patch(view, @images <> "?filter%3Afolder_path=images%2Flegacy%2Fpics")
      assert heading(view) == "pics"
      assert render(view) =~ "a.jpg"

      search(view, @image_search, "a.jpg")
      assert_patch(view, @images <> "?filter:folder_path=images%2Flegacy%2Fpics&filter:path=a.jpg")
      assert heading(view) == "pics"
      assert render(view) =~ "a.jpg"
      refute render(view) =~ "legacy-notes.jpg"
      refute render(view) =~ "Path: images/legacy/pics"

      search(view, @image_search, "")
      assert_patch(view, @images <> "?filter:folder_path=images%2Flegacy%2Fpics")
      assert heading(view) == "pics"
      assert has_element?(view, "#list-row-#{c.legacy.id}")
    end

    test "a folder link in the old shape still opens the folder, with no search", %{conn: conn} = c do
      {conn, _user} = reader(conn)
      old_link = @images <> "?filter:path=images/legacy/pics"
      conn_get = get(conn, @images, %{"filter:path" => "images/legacy/pics"})
      assert redirected_to(conn_get) == @images <> "?filter%3Afolder_path=images%2Flegacy%2Fpics"

      {:ok, view, html} = live(conn, old_link)
      assert heading(view) == "pics"
      assert has_element?(view, "#list-row-#{c.legacy.id}")
      refute has_element?(view, "#list-row-#{c.loose.id}")
      refute html =~ "Path: images/legacy/pics"
    end

    # A search inside a folder, and one that doesn't start with the library's
    # root, were never a folder link
    test "a search link in the old shape still searches", %{conn: conn} = c do
      {conn, _user} = reader(conn)

      for query <- ["filter:path=legacy", "filter:folder_id=root&filter:path=images/legacy/pics"] do
        {:ok, view, html} = live(conn, @images <> "?" <> query)
        assert heading(view) == "Root folder"
        assert html =~ "Path: "
        assert has_element?(view, "#list-row-#{c.legacy.id}")
      end
    end
  end

  # An editor's first view files the legacy image into its folder, which
  # leaves the root empty
  describe "the Images library, for an editor" do
    setup do
      Factory.insert(:image, status: :processed, path: "images/legacy/pics/a.jpg", folder_id: nil)
      :ok
    end

    # Starting with the library's root doesn't make a search a folder link:
    # an image's own path names no folder
    test "a link searching for an image's path still searches", %{conn: conn} do
      {:ok, view, html} = live(conn, @images <> "?filter:path=images/legacy/pics/a.jpg")

      assert heading(view) == "Root folder"
      assert html =~ "Path: images/legacy/pics/a.jpg"
      refute Repo.get_by(Brando.Media.Folder, scope: "images", path: "legacy/pics/a.jpg")
    end

    # The root has no loose images, which on a bare arrival opens the default
    # upload folder: a search searches the root it names instead
    test "a search link at an empty root stays at the root", %{conn: conn} do
      {:ok, view, html} = live(conn, @images <> "?filter:path=legacy")

      assert heading(view) == "Root folder"
      assert html =~ "Path: legacy"
    end
  end

  # Files search by `filter:filename`, so a `filter:path` was only ever a
  # folder link
  describe "the Files library" do
    setup do
      folder_id = FolderBrowser.folder_id_for("files/default/terms")

      file =
        Repo.insert!(%Brando.Files.File{
          filename: "terms.pdf",
          filesize: 1,
          config_target: "default",
          folder_id: folder_id
        })

      {:ok, folder_id: folder_id, terms: file}
    end

    test "a folder link in the old shape opens the folder", %{conn: conn} = c do
      conn_get = get(conn, "/admin/assets/files", %{"filter:path" => "files/default/terms"})
      assert redirected_to(conn_get) == "/admin/assets/files?filter%3Afolder_id=#{c.folder_id}"

      {:ok, view, _html} = live(conn, "/admin/assets/files?filter:path=files/default/terms")
      assert heading(view) == "terms"
      assert has_element?(view, "#list-row-#{c.terms.id}")
    end

    test "a folder known by its path holds no files", %{conn: conn} = c do
      {:ok, view, _html} = live(conn, "/admin/assets/files?filter:folder_path=files/default/made/up")
      refute has_element?(view, "#list-row-#{c.terms.id}")
    end
  end
end

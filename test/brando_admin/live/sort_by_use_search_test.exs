defmodule BrandoAdmin.SortByUseSearchTest do
  @moduledoc """
  "Sort by use" sorts the folder in view, every asset in it. A search lists
  only the matching ones, so while a search is on the libraries offer no
  sort, as under the "Not in use" filter. Clearing the search offers it
  again, and an empty search is no search.
  """
  # Grouped, one at a time: a media list inserts the folders of the upload
  # paths (BrandoAdmin.Images.FolderBrowser), unique by path, which
  # concurrent transactions would wait on
  use Brando.LiveCase, async: true, group: :shared_locks

  alias Brando.Repo
  alias BrandoAdmin.Images.FolderBrowser

  @sort "button[phx-click=sweep_open]"

  defp search(view, form, query), do: view |> form(form, %{q: query}) |> render_change()

  defp assert_search_hides_sort(conn, path, form, query) do
    {:ok, view, _html} = live(conn, path)
    assert has_element?(view, @sort)

    search(view, form, query)
    refute has_element?(view, @sort)

    search(view, form, "")
    assert has_element?(view, @sort)
  end

  describe "the Videos library" do
    setup do
      folder_id = FolderBrowser.folder_id_for("videos/default/clips")
      Factory.insert(:video, folder_id: folder_id, title: "Intervju i Bergen")
      Factory.insert(:video, folder_id: folder_id, title: "Konsert")
      {:ok, path: "/admin/assets/videos?filter:folder_id=#{folder_id}"}
    end

    test "a search hides Sort by use, and clearing it shows it again", %{conn: conn, path: path} do
      assert_search_hides_sort(conn, path, "#listing-filter-form-Elixir\\.Brando\\.Videos\\.Video-path", "intervju")
    end

    test "a search in the URL hides it, an empty one doesn't", %{conn: conn, path: path} do
      {:ok, view, _html} = live(conn, path <> "&filter:path=intervju")
      refute has_element?(view, @sort)

      {:ok, view, _html} = live(conn, path <> "&filter:path=")
      assert has_element?(view, @sort)
    end
  end

  describe "the Images library" do
    setup do
      folder_id = FolderBrowser.folder_id_for("images/site/default")
      Factory.insert(:image, folder_id: folder_id, status: :processed, path: "images/site/default/intervju.jpg")
      Factory.insert(:image, folder_id: folder_id, status: :processed, path: "images/site/default/konsert.jpg")
      {:ok, path: "/admin/assets/images?filter:folder_id=#{folder_id}"}
    end

    test "a path search hides Sort by use, and clearing it shows it again", %{conn: conn, path: path} do
      assert_search_hides_sort(conn, path, "#listing-filter-form-Elixir\\.Brando\\.Images\\.Image-path", "intervju")
    end

    test "a config target search hides it too", %{conn: conn, path: path} do
      form = "#listing-filter-form-Elixir\\.Brando\\.Images\\.Image-config_target_search"
      assert_search_hides_sort(conn, path, form, "default")
    end

    test "a search in the URL hides it, an empty one doesn't", %{conn: conn, path: path} do
      {:ok, view, _html} = live(conn, path <> "&filter:path=intervju")
      refute has_element?(view, @sort)

      {:ok, view, _html} = live(conn, path <> "&filter:path=")
      assert has_element?(view, @sort)
    end
  end

  describe "the Files library" do
    setup do
      folder_id = FolderBrowser.folder_id_for("files/default/docs")

      for name <- ["intervju.pdf", "konsert.pdf"] do
        Repo.insert!(%Brando.Files.File{filename: name, filesize: 1, config_target: "default", folder_id: folder_id})
      end

      {:ok, path: "/admin/assets/files?filter:folder_id=#{folder_id}"}
    end

    test "a filename search hides Sort by use, and clearing it shows it again", %{conn: conn, path: path} do
      assert_search_hides_sort(conn, path, "#listing-filter-form-Elixir\\.Brando\\.Files\\.File-filename", "intervju")
    end

    test "a search in the URL hides it, an empty one doesn't", %{conn: conn, path: path} do
      {:ok, view, _html} = live(conn, path <> "&filter:filename=intervju")
      refute has_element?(view, @sort)

      {:ok, view, _html} = live(conn, path <> "&filter:filename=")
      assert has_element?(view, @sort)
    end
  end
end

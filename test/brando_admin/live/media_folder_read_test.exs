defmodule BrandoAdmin.MediaFolderReadTest do
  # A media library or picker drawing a folder used to store it: the folder
  # on screen got a row (for its upload button's `data-folder-id`), and the
  # image library filed legacy images, found by their paths, into folders it
  # created. Drawing is reading, so a user who may only read the media now
  # leaves no folders behind; a folder not stored yet shows empty, and its
  # images are found by their paths as before. Adding or organizing media
  # still stores the folder on screen, for the uploads into it.
  use Brando.LiveCase

  import Brando.Test.Users

  import Ecto.Query

  alias Brando.Images.Image
  alias Brando.Media.Folder
  alias Brando.Repo
  alias BrandoAdmin.Components.ImagePicker

  @page ~w(brando.pages.read brando.pages.update)

  setup do
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, :none)

    # Uploaded before folders were stored: in a folder by its path only
    legacy = Factory.insert(:image, status: :processed, path: "images/legacy/pics/a.jpg", folder_id: nil)
    {:ok, legacy: legacy}
  end

  defp folder_count, do: Repo.aggregate(Folder, :count)
  defp folder_of(%Image{id: id}), do: Repo.one(from(i in Image, where: i.id == ^id, select: i.folder_id))
  defp stored?(path), do: Repo.one(from(f in Folder, where: f.scope == "images" and f.path == ^path, select: count())) > 0

  defp open_library(conn, query) do
    {:ok, view, html} = live(conn, "/admin/assets/images?" <> query)
    {view, html}
  end

  describe "the image library" do
    test "opened by a reader stores no folders and files no images", %{conn: conn} = c do
      {conn, _user} = log_in_as(conn, permissions: ~w(brando.images.read))
      folders = folder_count()

      {view, html} = open_library(conn, "filter:path=images/legacy/pics")

      # The folder shows, with its image, though nothing was stored for it
      assert html =~ "a.jpg"

      render_click(view, "assets_go_parent", %{})
      render_click(view, "sweep_open", %{})
      {_view, _html} = open_library(conn, "filter:folder_id=root")

      assert folder_count() == folders
      refute stored?("legacy/pics")
      assert folder_of(c.legacy) == nil
    end

    test "a folder not stored yet shows empty to a reader", %{conn: conn} do
      {conn, _user} = log_in_as(conn, permissions: ~w(brando.images.read))
      folders = folder_count()

      {_view, html} = open_library(conn, "filter:path=images/made/up")

      refute html =~ "a.jpg"
      assert folder_count() == folders
    end

    test "opened by someone who may add images stores the folder on screen, for uploads", %{conn: conn} do
      {conn, _user} = log_in_as(conn, permissions: ~w(brando.images.read brando.images.create))

      {view, _html} = open_library(conn, "filter:path=images/legacy/pics")

      assert stored?("legacy/pics")
      assert has_element?(view, "#library-image-upload[data-folder-id]")
    end

    test "opened by someone who may organize images files the legacy ones", %{conn: conn} = c do
      {conn, _user} = log_in_as(conn, permissions: ~w(brando.images.read brando.images.update))

      open_library(conn, "filter:folder_id=root")

      assert folder_of(c.legacy) ==
               Repo.one(from(f in Folder, where: f.scope == "images" and f.path == "legacy/pics", select: f.id))
    end
  end

  describe "the file library" do
    test "opened by a reader stores no folders", %{conn: conn} do
      {conn, _user} = log_in_as(conn, permissions: ~w(brando.files.read))
      folders = folder_count()

      {:ok, _view, _html} = live(conn, "/admin/assets/files?filter:folder_id=root")

      assert folder_count() == folders
    end
  end

  describe "the image picker in an entry form" do
    test "opened by a reader stores no folders", %{conn: conn} do
      {conn, _user} = log_in_as(conn, permissions: @page ++ ~w(brando.images.read))
      page = Factory.insert(:page)
      {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
      folders = folder_count()

      opening = %{config_target: "default", event_target: "field", multi: false, selected_images: []}
      send(view.pid, {:phoenix, :send_update, {{ImagePicker, "image-picker"}, opening}})
      render(view)
      view |> with_target(cid_of(view, "#image-picker")) |> render_click("go_folder", %{"folder" => "legacy/pics"})

      assert folder_count() == folders
    end
  end
end

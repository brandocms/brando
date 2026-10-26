defmodule BrandoAdmin.MediaAuthorizationTest do
  # With group authorization, the media pickers in an entry form and the
  # media libraries change library assets only with a grant on them: the
  # view's event check never sees a picker's events (they go to a
  # LiveComponent), so the context functions check the actor themselves.
  use Brando.LiveCase

  import Brando.Test.Users

  import Ecto.Query

  alias Brando.Images.Image
  alias Brando.Media.Folder
  alias Brando.Repo
  alias Brando.Videos.Video
  alias BrandoAdmin.Components.ImagePicker
  alias BrandoAdmin.Components.VideoPicker
  alias BrandoAdmin.Images.FolderBrowser

  @page ~w(brando.pages.read brando.pages.update)

  setup do
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, :none)

    %{
      page: Factory.insert(:page),
      image: Factory.insert(:image, status: :processed, path: "images/site/default/a.jpg"),
      other_image: Factory.insert(:image, status: :processed),
      video:
        Factory.insert(:video,
          title: "Original title",
          config_target: "default",
          folder_id: FolderBrowser.folder_id_for("default", "videos")
        )
    }
  end

  defp folder_of(%schema{id: id}), do: Repo.one(from(a in schema, where: a.id == ^id, select: a.folder_id))
  defp folder_count, do: Repo.aggregate(Folder, :count)

  defp open_form(conn, page) do
    {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
    view
  end

  # As a field opening them does (`send_update/2`)
  defp open_pickers(view) do
    opening = %{config_target: "default", event_target: "field", multi: false}
    send(view.pid, {:phoenix, :send_update, {{ImagePicker, "image-picker"}, Map.put(opening, :selected_images, [])}})
    send(view.pid, {:phoenix, :send_update, {{VideoPicker, "video-picker"}, Map.put(opening, :selected_videos, [])}})
    render(view)
  end

  defp picker(view, id), do: with_target(view, cid_of(view, "##{id}"))

  describe "pickers in an entry form" do
    test "without media grants nothing is deleted, renamed, moved or created", %{conn: conn} = c do
      {conn, _user} = log_in_as(conn, permissions: @page)
      view = open_form(conn, c.page)
      # Opening a picker files its root folder
      open_pickers(view)
      folders = folder_count()
      image_folder = folder_of(c.other_image)
      video_folder = folder_of(c.video)

      view |> picker("image-picker") |> render_click("delete_image_from_picker", %{"id" => c.image.id})
      view |> picker("video-picker") |> render_click("rename_video", %{"video_id" => c.video.id, "title" => "Renamed"})

      view
      |> picker("image-picker")
      |> render_click("picker_move_to_folder", %{"folder" => "moved", "ids" => [c.other_image.id]})

      view
      |> picker("video-picker")
      |> render_click("picker_move_to_folder", %{"folder" => "moved", "ids" => [c.video.id]})

      view |> picker("image-picker") |> render_click("create_folder", %{"folder" => %{"name" => "new"}})
      view |> picker("image-picker") |> render_click("go_folder", %{"folder" => "made-up"})
      open_pickers(view)

      refute Repo.get!(Image, c.image.id).deleted_at
      assert Repo.get!(Video, c.video.id).title == "Original title"
      assert folder_of(c.other_image) == image_folder
      assert folder_of(c.video) == video_folder
      assert folder_count() == folders
    end

    test "the controls are offered only with the grants", %{conn: conn} = c do
      {conn, _user} = log_in_as(conn, permissions: @page ++ ~w(brando.images.read brando.videos.read))
      html = conn |> open_form(c.page) |> open_pickers()

      assert html =~ "image-picker-image-menu-#{c.image.id}"
      assert html =~ "video-picker-menu-#{c.video.id}"
      refute html =~ "delete_image_from_picker"
      refute html =~ "delete_video_from_picker"
      refute html =~ "start_rename"
      refute html =~ "new-folder-trigger"

      grants = ~w(brando.images.update brando.images.delete brando.videos.update brando.videos.delete)
      {conn, _user} = log_in_as(build_conn(), permissions: @page ++ ~w(brando.images.read brando.videos.read) ++ grants)
      html = conn |> open_form(c.page) |> open_pickers()

      assert html =~ "delete_image_from_picker"
      assert html =~ "delete_video_from_picker"
      assert html =~ "start_rename"
      assert html =~ "new-folder-trigger"
    end

    test "with media grants they are", %{conn: conn} = c do
      grants = ~w(brando.images.read brando.images.update brando.images.delete brando.videos.read brando.videos.update)
      {conn, _user} = log_in_as(conn, permissions: @page ++ grants)
      view = open_form(conn, c.page)
      image_folder = folder_of(c.other_image)
      video_folder = folder_of(c.video)

      view |> picker("image-picker") |> render_click("delete_image_from_picker", %{"id" => c.image.id})
      view |> picker("video-picker") |> render_click("rename_video", %{"video_id" => c.video.id, "title" => "Renamed"})

      view
      |> picker("image-picker")
      |> render_click("picker_move_to_folder", %{"folder" => "moved", "ids" => [c.other_image.id]})

      view
      |> picker("video-picker")
      |> render_click("picker_move_to_folder", %{"folder" => "moved", "ids" => [c.video.id]})

      assert Repo.get!(Image, c.image.id).deleted_at
      assert Repo.get!(Video, c.video.id).title == "Renamed"
      refute folder_of(c.other_image) == image_folder
      refute folder_of(c.video) == video_folder
    end
  end

  describe "media library" do
    test "reading alone neither moves images nor creates folders", %{conn: conn} = c do
      {conn, _user} = log_in_as(conn, permissions: ~w(brando.images.read))
      {:ok, view, html} = live(conn, "/admin/assets/images?filter:folder_id=root")
      folders = folder_count()

      refute html =~ "new-folder-trigger"
      refute html =~ "Cut selected"

      folder = folder_of(c.image)

      render_click(view, "assets_move_selected_to_folder", %{"folder" => "moved", "ids" => [c.image.id]})
      render_click(view, "assets_cut_selected", %{"ids" => [c.image.id]})
      render_click(view, "assets_paste_selected", %{})
      render_submit(view, "assets_create_folder", %{"folder" => %{"name" => "new"}})
      render_click(view, "assets_go_folder", %{"folder" => "made-up"})

      assert folder_of(c.image) == folder
      assert folder_count() == folders
    end

    test "updating moves images and creates folders", %{conn: conn} = c do
      {conn, _user} = log_in_as(conn, permissions: ~w(brando.images.read brando.images.update))
      {:ok, view, html} = live(conn, "/admin/assets/images?filter:folder_id=root")
      folders = folder_count()
      folder = folder_of(c.image)

      assert html =~ "new-folder-trigger"

      render_click(view, "assets_move_selected_to_folder", %{"folder" => "moved", "ids" => [c.image.id]})
      render_submit(view, "assets_create_folder", %{"folder" => %{"name" => "new"}})

      refute folder_of(c.image) == folder
      assert folder_count() > folders
    end

    test "Images.duplicate_image/2 takes the create grant", c do
      reader = insert_user(permissions: ~w(brando.admin.access brando.images.read))
      creator = insert_user(permissions: ~w(brando.admin.access brando.images.read brando.images.create))
      count = Repo.aggregate(Image, :count)

      assert {:error, :forbidden} = Brando.Images.duplicate_image(c.image.id, reader)
      assert Repo.aggregate(Image, :count) == count

      # Past the check: the test image has no file to copy
      refute Brando.Images.duplicate_image(c.image.id, creator) == {:error, :forbidden}
    end

    test "Images.delete_images/2 deletes only with the delete grant", c do
      reader = insert_user(permissions: ~w(brando.admin.access brando.images.read))
      deleter = insert_user(permissions: ~w(brando.admin.access brando.images.read brando.images.delete))

      assert {:error, :forbidden} = Brando.Images.delete_images([c.image.id], reader)
      refute Repo.get!(Image, c.image.id).deleted_at

      assert {1, _} = Brando.Images.delete_images([c.image.id], deleter)
      assert Repo.get!(Image, c.image.id).deleted_at
    end
  end
end

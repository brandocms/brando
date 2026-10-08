defmodule BrandoAdmin.LiveView.Form.ProcessingWatchTest do
  # The form LiveView's half of following assets in processing: which reports
  # reach which components, and when the subscription ends. The image path is
  # covered end to end, with two editors, in
  # `test/brando_admin/live/processing_status_sync_test.exs`; a video's
  # provider cannot run in tests, so its report is sent here the way
  # `ProviderUpdate` sends it.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Factory

  alias Brando.Assets.ProcessingStatus
  alias Brando.JSONLDTest.Post
  alias Brando.MigrationTest.ProjectUpdate1
  alias Brando.Videos.Uploaders.ProviderUpdate
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.LiveView.Form.ProcessingWatch
  alias Ecto.Changeset
  alias Phoenix.Component
  alias Phoenix.LiveView.Socket

  setup do
    {:ok, user: Factory.insert(:random_user)}
  end

  describe "a video another editor uploaded to its provider" do
    setup %{user: user} do
      video = Factory.insert(:upload_video, status: :uploading, creator_id: user.id)
      {:ok, video: video, field: {Input.Video, "page_clip"}}
    end

    test "every report reaches the field until the video is ready", %{video: video, field: field} do
      socket = follow(socket(), :video, field, [video.id])
      assert subscribers(:video, video.id) == [self()]

      {:ok, video} = ProviderUpdate.update_video(video, %{status: :processing})
      socket = handle(socket)
      assert_receive {:phoenix, :send_update, {^field, %{event: "video_processed", video: %{status: :processing}}}}
      assert subscribers(:video, video.id) == [self()]

      {:ok, _video} = ProviderUpdate.update_video(video, %{status: :ready, width: 1280, height: 720})
      socket = handle(socket)
      assert_receive {:phoenix, :send_update, {^field, %{event: "video_processed", video: %{status: :ready}}}}

      assert socket.assigns.processing_watch == %{}
      assert subscribers(:video, video.id) == []
    end

    test "the field takes the report only for the video it shows", %{video: video} do
      ready = %{video | status: :ready, width: 1280, height: 720}
      other = %{ready | id: video.id + 1}
      field = Component.to_form(%{}, as: "page")[:clip]
      socket = %Socket{assigns: %{__changed__: %{}, video: video, id: "page_clip", field: field, form_id: "page_form"}}

      assert {:ok, %{assigns: %{video: ^video}}} = Input.Video.update(%{event: "video_processed", video: other}, socket)
      refute_received {:phoenix, :send_update, _}

      # The form takes it too, into its changeset and entry for the live preview.
      assert {:ok, %{assigns: %{video: ^ready}}} = Input.Video.update(%{event: "video_processed", video: ready}, socket)

      assert_received {:phoenix, :send_update,
                       {{BrandoAdmin.Components.Form, "page_form"},
                        %{event: "entry_field_asset_processed", field: :clip, path: [], asset: ^ready}}}
    end
  end

  describe "a video field showing a video that is not ready" do
    setup %{user: user} do
      video = Factory.insert(:upload_video, status: :processing, creator_id: user.id)
      field = Component.to_form(Changeset.change(%Post{cover_video_id: video.id, cover_video: video}))[:cover_video]
      {:ok, socket} = Input.Video.mount(%Socket{assigns: %{__changed__: %{}}})
      {:ok, socket} = Input.Video.update(%{id: "post_cover_video", field: field}, socket)
      {:ok, field: field, socket: socket}
    end

    test "does not read it on each update in a form LiveView", %{field: field, socket: socket} do
      Process.put(ProcessingWatch, true)
      on_exit(fn -> Process.delete(ProcessingWatch) end)

      queries = count_queries()
      {:ok, _socket} = Input.Video.update(%{id: "post_cover_video", field: field}, socket)
      assert queries.() == 0
    end

    test "reads it on each update anywhere else", %{field: field, socket: socket} do
      queries = count_queries()
      {:ok, _socket} = Input.Video.update(%{id: "post_cover_video", field: field}, socket)
      assert queries.() == 1
    end
  end

  describe "an image" do
    setup %{user: user} do
      {:ok, image: Factory.insert(:image, creator: user, status: :unprocessed)}
    end

    test "two components follow it on one subscription, and the last to leave ends it", %{image: image} do
      field = {Input.Image, "page_meta_image"}
      ref = {Input.Blocks.PictureBlock, "ref"}

      socket = socket() |> follow(:image, field, [image.id]) |> follow(:image, ref, [image.id])
      assert subscribers(:image, image.id) == [self()]

      socket = follow(socket, :image, field, [])
      assert subscribers(:image, image.id) == [self()]

      socket = follow(socket, :image, ref, [])
      assert subscribers(:image, image.id) == []
      assert socket.assigns.processing_watch == %{}
    end

    test "a failed processing keeps the watch, so a later pass still reports", %{image: image} do
      field = {Input.Image, "page_meta_image"}
      socket = follow(socket(), :image, field, [image.id])

      ProcessingStatus.broadcast(:image, image, :failed)
      socket = handle(socket)

      refute_receive {:phoenix, :send_update, _}
      assert Map.has_key?(socket.assigns.processing_watch, {:image, image.id})
      assert subscribers(:image, image.id) == [self()]

      # The drawer requeues the image, and this pass succeeds.
      ProcessingStatus.broadcast(:image, %{image | status: :processed}, :done)
      socket = handle(socket)

      assert_receive {:phoenix, :send_update, {^field, %{event: "image_processed", image: %{status: :processed}}}}
      assert socket.assigns.processing_watch == %{}
      assert subscribers(:image, image.id) == []
    end

    test "an entry gallery takes the processed image into its object", %{image: image} do
      processed = %{image | status: :processed}
      other = %{image_id: image.id + 1, image: %{image | id: image.id + 1}}

      socket = %Socket{
        assigns: %{__changed__: %{}, id: "page_photos", gallery_objects: [%{image_id: image.id, image: image}, other]}
      }

      assert {:ok, socket} = Input.Gallery.update(%{event: "image_processed", image: processed}, socket)
      assert socket.assigns.gallery_objects == [%{image_id: image.id, image: processed}, other]
    end

    test "images processed before the watch began are reported at once, read in one query", %{user: user, image: image} do
      second = Factory.insert(:image, creator: user, status: :unprocessed)
      {:ok, image} = Brando.Images.update_image(image, %{status: :processed}, :system)
      {:ok, second} = Brando.Images.update_image(second, %{status: :processed}, :system)
      field = {Input.Image, "page_meta_image"}
      ref = {Input.Blocks.PictureBlock, "ref"}

      # Two components rendering at once, as on opening an entry.
      socket = socket() |> follow(:image, field, [image.id]) |> follow(:image, ref, [second.id])
      assert_received :processing_watch_catch_up
      refute_received :processing_watch_catch_up

      queries = count_queries()
      {:halt, socket} = ProcessingWatch.handle_info(:processing_watch_catch_up, socket)
      assert queries.() == 1

      assert_received {:phoenix, :send_update, {^field, %{event: "image_processed", image: %{id: id}}}}
      assert id == image.id
      assert_received {:phoenix, :send_update, {^ref, %{event: "image_processed", image: %{id: id}}}}
      assert id == second.id
      assert socket.assigns.processing_watch == %{}
      assert subscribers(:image, image.id) == []
    end
  end

  describe "the form, told an entry gallery's image is processed" do
    setup %{user: user} do
      {:ok,
       stored: Factory.insert(:image, creator: user, status: :unprocessed),
       added: Factory.insert(:image, creator: user, status: :unprocessed)}
    end

    test "refreshes stored and unsaved objects in the changeset and the entry", %{
      user: user,
      stored: stored,
      added: added
    } do
      object = Ecto.put_meta(%Brando.Galleries.GalleryObject{id: 1, image_id: stored.id, image: stored}, state: :loaded)
      gallery = Ecto.put_meta(%Brando.Galleries.Gallery{id: 1, gallery_objects: [object]}, state: :loaded)
      entry = %ProjectUpdate1{photos: gallery}
      socket = gallery_form_socket(user, entry)

      # Another editor's upload, added to the gallery and not yet saved.
      {:ok, socket} = Form.update(gallery_delivery(added), socket)

      socket =
        Enum.reduce([stored, added], socket, fn image, socket ->
          {:ok, socket} = Form.update(gallery_processed(%{image | status: :processed}), socket)
          socket
        end)

      applied = Changeset.apply_changes(socket.assigns.form.source)
      assert image_status(applied, stored) == :processed
      assert image_status(applied, added) == :processed
      assert image_status(socket.assigns.entry, stored) == :processed
    end
  end

  describe "an image field given a copy of its image with another status" do
    setup do
      processed = %Brando.Images.Image{
        id: 7,
        status: :processed,
        path: "images/a.jpg",
        width: 400,
        height: 300,
        focal: %Brando.Images.Focal{x: 50, y: 50},
        updated_at: ~N[2026-10-08 12:00:10]
      }

      {:ok, socket} = Input.Image.mount(%Socket{assigns: %{__changed__: %{}}})
      socket = Component.assign(socket, image: processed, image_id: 7, focal: {50, 50}, form_id: "page_form")
      {:ok, processed: processed, socket: socket}
    end

    test "takes a newer unprocessed copy, as after a crop reset it", %{processed: processed, socket: socket} do
      reset = %{processed | status: :unprocessed, updated_at: ~N[2026-10-08 12:00:15]}
      {:ok, socket} = Input.Image.update(%{id: "page_meta_image", field: meta_image_field(reset)}, socket)
      assert socket.assigns.image.status == :unprocessed
    end

    test "keeps its processed copy over an older unprocessed one", %{processed: processed, socket: socket} do
      stale = %{processed | status: :unprocessed, updated_at: ~N[2026-10-08 12:00:05]}
      {:ok, socket} = Input.Image.update(%{id: "page_meta_image", field: meta_image_field(stale)}, socket)
      assert socket.assigns.image.status == :processed

      # Read in the same second: the processed copy wins.
      tie = %{processed | status: :unprocessed}
      {:ok, socket} = Input.Image.update(%{id: "page_meta_image", field: meta_image_field(tie)}, socket)
      assert socket.assigns.image.status == :processed
    end
  end

  test "a component asks to follow only the assets still processing, and only when that changes" do
    Process.put(ProcessingWatch, true)
    on_exit(fn -> Process.delete(ProcessingWatch) end)

    processing = %Brando.Images.Image{id: 1, status: :unprocessed}
    processed = %Brando.Images.Image{id: 2, status: :processed}
    socket = %Socket{transport_pid: self(), assigns: %{__changed__: %{}, id: "page_meta_image"}}

    socket = ProcessingWatch.watch(socket, Input.Image, :image, [processing, processed, nil])
    assert_receive {:processing_watch, :image, {Input.Image, "page_meta_image"}, ids}
    assert ids == MapSet.new([1])

    socket = ProcessingWatch.watch(socket, Input.Image, :image, [processing])
    refute_receive {:processing_watch, _, _, _}

    ProcessingWatch.watch(socket, Input.Image, :image, [%{processing | status: :processed}])
    assert_receive {:processing_watch, :image, _target, ids}
    assert ids == MapSet.new()
  end

  defp gallery_form_socket(user, entry) do
    %Socket{}
    |> Component.assign(:form, Component.to_form(Changeset.change(entry)))
    |> Component.assign(:entry, entry)
    |> Component.assign(:schema, ProjectUpdate1)
    |> Component.assign(:singular, "project")
    |> Component.assign(:current_user, user)
    |> Component.assign(:processing_images, [])
    |> Component.assign(:dirty_fields, [])
    |> Component.assign(:has_blocks?, false)
    |> Component.assign(:live_preview_active?, false)
    |> Component.assign(:updated_entry_assocs, %{})
  end

  defp gallery_delivery(image),
    do: %{event: "entry_field_upload_complete", asset_type: :gallery, field: :photos, path: [], asset: image}

  defp gallery_processed(image), do: %{event: "entry_gallery_image_processed", field: :photos, path: [], image: image}

  defp image_status(entry, image) do
    entry.photos.gallery_objects |> Enum.find(&(&1.image_id == image.id)) |> Map.fetch!(:image) |> Map.fetch!(:status)
  end

  defp meta_image_field(image) do
    page = %Brando.Pages.Page{meta_image_id: image.id, meta_image: image}
    Component.to_form(Changeset.change(page), as: "page")[:meta_image]
  end

  defp socket, do: %Socket{assigns: %{__changed__: %{}, processing_watch: %{}, processing_catch_up: %{}}}

  # Counts the repo queries this process makes from now on.
  defp count_queries do
    owner = self()
    handler = {__MODULE__, make_ref()}
    event = Brando.repo().config()[:telemetry_prefix] ++ [:query]
    :telemetry.attach(handler, event, fn _, _, _, _ -> send(owner, {:query, handler}) end, nil)
    on_exit(fn -> :telemetry.detach(handler) end)

    fn ->
      :telemetry.detach(handler)
      count = fn count, again -> receive(do: ({:query, ^handler} -> again.(count + 1, again)), after: (0 -> count)) end
      count.(0, count)
    end
  end

  defp follow(socket, kind, target, ids) do
    {:halt, socket} = ProcessingWatch.handle_info({:processing_watch, kind, target, MapSet.new(ids)}, socket)
    socket
  end

  # The report the subscription brought this process.
  defp handle(socket) do
    assert_receive {:asset_processing, _kind, _asset, _state} = report
    {:halt, socket} = ProcessingWatch.handle_info(report, socket)
    socket
  end

  defp subscribers(kind, id),
    do: Brando.pubsub() |> Registry.lookup(ProcessingStatus.topic(kind, id)) |> Enum.map(&elem(&1, 0))
end

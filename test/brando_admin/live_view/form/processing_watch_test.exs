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
  alias Brando.Videos.Uploaders.ProviderUpdate
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.LiveView.Form.ProcessingWatch
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
      socket = %Socket{assigns: %{__changed__: %{}, video: video, id: "page_clip"}}

      assert {:ok, %{assigns: %{video: ^video}}} = Input.Video.update(%{event: "video_processed", video: other}, socket)
      assert {:ok, %{assigns: %{video: ^ready}}} = Input.Video.update(%{event: "video_processed", video: ready}, socket)
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

    test "a failed processing ends the watch without a report", %{image: image} do
      field = {Input.Image, "page_meta_image"}
      socket = follow(socket(), :image, field, [image.id])

      ProcessingStatus.broadcast(:image, image, :failed)
      socket = handle(socket)

      refute_receive {:phoenix, :send_update, _}
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

    test "an image processed before the watch began is reported at once", %{image: image} do
      {:ok, image} = Brando.Images.update_image(image, %{status: :processed}, :system)
      field = {Input.Image, "page_meta_image"}

      socket = follow(socket(), :image, field, [image.id])
      handle(socket)

      assert_receive {:phoenix, :send_update, {^field, %{event: "image_processed", image: %{status: :processed}}}}
      assert subscribers(:image, image.id) == []
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

  defp socket, do: %Socket{assigns: %{__changed__: %{}, processing_watch: %{}}}

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

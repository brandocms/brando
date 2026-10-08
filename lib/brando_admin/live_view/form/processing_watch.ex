defmodule BrandoAdmin.LiveView.Form.ProcessingWatch do
  @moduledoc """
  Follows the images and videos a form shows in processing, so that every
  editor with the entry open sees them finish, not only the editor who
  uploaded them.

  The uploading form learns that its own upload is processed through
  `"brando:image:<id>"`, which it subscribes to when the upload is delivered.
  Another editor never subscribed there: it got the asset's id through field
  sync, the edit session or a reload, and kept showing "Processing image…"
  until it reloaded the page.

  A field, ref or var that renders an asset calls `watch/4` from its `update`.
  While one of its assets is still processing, the form's LiveView subscribes
  to that asset's `Brando.Assets.ProcessingStatus` topic, and when a report
  comes it sends the component the asset as an update:

      %{event: "image_processed", image: image}
      %{event: "video_processed", video: video}

  The component replaces its asset only if it still shows the one reported.
  The subscription ends when processing does, when no component shows the
  asset in processing any more, and with the LiveView. A failed processing
  keeps it: the image is still unprocessed, and processing it again (the
  image drawer requeues it) reports on the same topic.

  Components and LiveViews outside the form hooks call `watch/4` too; it does
  nothing there, since nothing would handle the reports.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, send_update: 2]

  alias Brando.Assets.ProcessingStatus

  @enabled __MODULE__

  @doc """
  Attaches the watch to a form LiveView (`BrandoAdmin.LiveView.Form.Hooks`).
  """
  def attach(socket) do
    if connected?(socket), do: Process.put(@enabled, true)

    socket
    |> assign(:processing_watch, %{})
    |> assign(:processing_catch_up, %{})
    |> attach_hook(:b_form_processing_watch, :handle_info, &handle_info/2)
  end

  @doc """
  Is the watch running in this process? Only in a connected form LiveView.
  """
  def enabled?, do: Process.get(@enabled, false)

  @doc """
  Follows the `kind` assets among `assets` that are still processing, for the
  component `module` with the id in its `:id` assign, and stops following the
  ones it followed before and no longer shows in processing.

  Call it from the component's `update` with every asset of that kind it
  renders. `nil`s are ignored. Sends the LiveView a message only when the set
  of assets changes.
  """
  def watch(%{assigns: assigns} = socket, module, kind, assets) when kind in [:image, :video] do
    key = watch_key(kind)

    if connected?(socket) and enabled?() do
      ids =
        assets
        |> Enum.filter(&ProcessingStatus.processing?(kind, &1))
        |> MapSet.new(& &1.id)

      if ids == Map.get(assigns, key, MapSet.new()) do
        socket
      else
        send(self(), {:processing_watch, kind, {module, assigns.id}, ids})
        assign(socket, key, ids)
      end
    else
      socket
    end
  end

  defp watch_key(:image), do: :processing_watch_images
  defp watch_key(:video), do: :processing_watch_videos

  @doc false
  def handle_info({:processing_watch, kind, target, ids}, socket) do
    {:halt, update_watch(socket, kind, target, ids)}
  end

  def handle_info({:asset_processing, kind, asset, state}, socket) do
    {:halt, report(socket, kind, asset, state)}
  end

  def handle_info(:processing_watch_catch_up, socket) do
    {:halt, catch_up(socket)}
  end

  def handle_info(_message, socket), do: {:cont, socket}

  # A failed image is still unprocessed and still shown so, and a later pass
  # (the drawer requeues it) reports on the same topic. Its watchers keep
  # their subscription, as their components keep showing it in processing
  # and would not ask again.
  defp report(socket, _kind, _asset, :failed), do: socket

  defp report(socket, kind, asset, state) do
    key = {kind, asset.id}
    targets = Map.get(socket.assigns.processing_watch, key, MapSet.new())

    if MapSet.size(targets) > 0 do
      asset = loaded(kind, asset)
      Enum.each(targets, &deliver(&1, kind, asset))
    end

    if state == :done and MapSet.size(targets) > 0 do
      ProcessingStatus.unsubscribe(kind, asset.id)
      assign(socket, :processing_watch, Map.delete(socket.assigns.processing_watch, key))
    else
      socket
    end
  end

  # `target` now watches exactly `ids`: it leaves the assets it no longer
  # shows in processing, and joins the new ones. A topic is subscribed by the
  # first component watching its asset and unsubscribed with the last.
  defp update_watch(socket, kind, target, ids) do
    watch = socket.assigns.processing_watch

    previous =
      for {{^kind, id}, targets} <- watch, MapSet.member?(targets, target), into: MapSet.new(), do: id

    watch =
      previous
      |> MapSet.difference(ids)
      |> Enum.reduce(watch, &leave(&2, {kind, &1}, target))

    joined = ids |> MapSet.difference(previous) |> Enum.reject(&Map.has_key?(watch, {kind, &1}))
    watch = ids |> MapSet.difference(previous) |> Enum.reduce(watch, &join(&2, {kind, &1}, target))

    socket
    |> assign(:processing_watch, watch)
    |> queue_catch_up(kind, joined)
  end

  defp leave(watch, {kind, id} = key, target) do
    targets = watch |> Map.get(key, MapSet.new()) |> MapSet.delete(target)

    if MapSet.size(targets) == 0 do
      ProcessingStatus.unsubscribe(kind, id)
      Map.delete(watch, key)
    else
      Map.put(watch, key, targets)
    end
  end

  defp join(watch, {kind, id} = key, target) do
    case Map.fetch(watch, key) do
      {:ok, targets} ->
        Map.put(watch, key, MapSet.put(targets, target))

      :error ->
        ProcessingStatus.subscribe(kind, id)
        Map.put(watch, key, MapSet.new([target]))
    end
  end

  # A component read its asset before this subscription existed, and a
  # report sent in between is gone. The new subscriptions are read again
  # once the components rendering now have all asked: their messages are
  # already queued ahead of the one sent here, so an entry opening with many
  # images in processing costs one query per kind, not one per image.
  defp queue_catch_up(socket, _kind, []), do: socket

  defp queue_catch_up(socket, kind, ids) do
    pending = socket.assigns.processing_catch_up
    if pending == %{}, do: send(self(), :processing_watch_catch_up)
    assign(socket, :processing_catch_up, Map.update(pending, kind, ids, &(&1 ++ ids)))
  end

  defp catch_up(socket) do
    pending = socket.assigns.processing_catch_up
    socket = assign(socket, :processing_catch_up, %{})

    Enum.reduce(pending, socket, fn {kind, ids}, socket ->
      kind
      |> fetch_all(Enum.filter(ids, &Map.has_key?(socket.assigns.processing_watch, {kind, &1})))
      |> Enum.reject(&ProcessingStatus.processing?(kind, &1))
      |> Enum.reduce(socket, &report(&2, kind, &1, :done))
    end)
  end

  # A provider reports the video as it was updated, without the thumbnail and
  # file a video field previews.
  defp loaded(:video, video) do
    case fetch_all(:video, [video.id]) do
      [video] -> video
      _ -> video
    end
  end

  defp loaded(:image, image), do: image

  defp fetch_all(_kind, []), do: []

  defp fetch_all(:image, ids) do
    {:ok, images} = Brando.Images.list_images(%{filter: %{ids: ids}})
    images
  end

  defp fetch_all(:video, ids) do
    {:ok, videos} = Brando.Videos.list_videos(%{filter: %{ids: ids}, preload: [:thumbnail, :file]})
    videos
  end

  defp deliver({module, id}, :image, image), do: send_update(module, id: id, event: "image_processed", image: image)
  defp deliver({module, id}, :video, video), do: send_update(module, id: id, event: "video_processed", video: video)
end

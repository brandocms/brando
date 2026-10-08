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
  asset in processing any more, and with the LiveView.

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
    |> attach_hook(:b_form_processing_watch, :handle_info, &handle_info/2)
  end

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

    if connected?(socket) and Process.get(@enabled, false) do
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
    key = {kind, asset.id}
    targets = Map.get(socket.assigns.processing_watch, key, MapSet.new())

    if state != :failed and MapSet.size(targets) > 0 do
      asset = loaded(kind, asset)
      Enum.each(targets, &deliver(&1, kind, asset))
    end

    socket =
      if state == :progress do
        socket
      else
        ProcessingStatus.unsubscribe(kind, asset.id)
        assign(socket, :processing_watch, Map.delete(socket.assigns.processing_watch, key))
      end

    {:halt, socket}
  end

  def handle_info(_message, socket), do: {:cont, socket}

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

    watch =
      ids
      |> MapSet.difference(previous)
      |> Enum.reduce(watch, &join(&2, {kind, &1}, target))

    assign(socket, :processing_watch, watch)
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
        catch_up(kind, id)
        Map.put(watch, key, MapSet.new([target]))
    end
  end

  # The component read the asset before this subscription existed, and a
  # report sent in between is gone. Read it again: if it has finished, report
  # it to ourselves as the topic would have.
  defp catch_up(kind, id) do
    case fetch(kind, id) do
      {:ok, asset} ->
        unless ProcessingStatus.processing?(kind, asset), do: send(self(), {:asset_processing, kind, asset, :done})

      _ ->
        :ok
    end
  end

  # A provider reports the video as it was updated, without the thumbnail and
  # file a video field previews.
  defp loaded(:video, video) do
    case fetch(:video, video.id) do
      {:ok, video} -> video
      _ -> video
    end
  end

  defp loaded(:image, image), do: image

  defp fetch(:image, id), do: Brando.Images.get_image(id)
  defp fetch(:video, id), do: Brando.Videos.get_video(%{matches: %{id: id}, preload: [:thumbnail, :file]})

  defp deliver({module, id}, :image, image), do: send_update(module, id: id, event: "image_processed", image: image)
  defp deliver({module, id}, :video, video), do: send_update(module, id: id, event: "video_processed", video: video)
end

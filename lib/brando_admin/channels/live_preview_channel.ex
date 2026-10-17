defmodule BrandoAdmin.LivePreviewChannel do
  @moduledoc """
  Channel for streaming Live Preview updates
  """
  use Phoenix.Channel
  alias Brando.Authorization.{Preview, Realtime}
  alias Brando.LivePreview

  intercept(["update", "rerender", "reload", "update_block"])

  @doc """
  Join live_preview channel for specific preview key
  """
  def join("live_preview:" <> preview_id, params, socket) do
    Realtime.allow_sandbox(socket)

    with true <- BrandoAdmin.AdminSocket.session_valid?(socket),
         :ok <- Preview.authorize(preview_id, socket.assigns.user_id) do
      Realtime.subscribe()
      send(self(), :sync_preview)

      socket =
        socket
        |> assign(:preview_id, preview_id)
        |> assign(:shown_version, params["version"])
        |> assign(:shown_patches, params["patches"] || 0)

      {:ok, socket.assigns.user_id, socket}
    else
      _ -> {:error, %{reason: "forbidden"}}
    end
  end

  def handle_out(event, payload, socket) do
    if Preview.authorize(socket.assigns.preview_id, socket.assigns.user_id) == :ok do
      push(socket, event, payload)
      {:noreply, socket}
    else
      {:stop, :normal, socket}
    end
  end

  # Recovery can render between the iframe's HTTP request and its channel join,
  # and an iframe that rejoins after a transport failure may have missed
  # renders. Replay the cache after subscribing when it is not the generation
  # the iframe says it shows (`LivePreview.page_state/1`); replaying the page it
  # was just served would morph the whole body for nothing, over what the
  # site's scripts have set up since.
  #
  # Block patches are not in the cache. When the iframe has not applied every
  # patch sent since the cache was written (it missed some, or it was served
  # the cache again on reload), the form renders the page again.
  def handle_info(:sync_preview, socket) do
    key = socket.assigns.preview_id
    state = LivePreview.page_state(key)

    case LivePreview.get_cache(key) do
      {:ok, html} when is_binary(html) ->
        replay? = state.generation != socket.assigns.shown_version
        shown_patches = if replay?, do: 0, else: socket.assigns.shown_patches

        if shown_patches != state.patches, do: LivePreview.report_lost_patches(key)
        if replay?, do: handle_out("rerender", %{html: html, v: state.generation}, socket), else: {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:authorization_changed, _}, socket) do
    if Preview.authorize(socket.assigns.preview_id, socket.assigns.user_id) == :ok,
      do: {:noreply, socket},
      else: {:stop, :normal, socket}
  end
end

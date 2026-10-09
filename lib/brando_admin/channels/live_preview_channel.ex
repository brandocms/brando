defmodule BrandoAdmin.LivePreviewChannel do
  @moduledoc """
  Channel for streaming Live Preview updates
  """
  use Phoenix.Channel
  alias Brando.Authorization.{Preview, Realtime}

  intercept(["update", "rerender", "reload", "update_block"])

  @doc """
  Join live_preview channel for specific preview key
  """
  def join("live_preview:" <> preview_id, _params, socket) do
    Realtime.allow_sandbox(socket)

    with true <- BrandoAdmin.AdminSocket.session_valid?(socket),
         :ok <- Preview.authorize(preview_id, socket.assigns.user_id) do
      Realtime.subscribe()
      send(self(), :sync_preview)
      {:ok, socket.assigns.user_id, assign(socket, :preview_id, preview_id)}
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

  # Recovery can render between the iframe's HTTP request and its channel join.
  # Replay the cache after subscribing so those updates are not lost, including
  # when an existing iframe rejoins after a transport failure.
  def handle_info(:sync_preview, socket) do
    case Brando.LivePreview.get_cache(socket.assigns.preview_id) do
      {:ok, html} when is_binary(html) -> handle_out("rerender", %{html: html}, socket)
      _ -> {:noreply, socket}
    end
  end

  def handle_info({:authorization_changed, _}, socket) do
    if Preview.authorize(socket.assigns.preview_id, socket.assigns.user_id) == :ok,
      do: {:noreply, socket},
      else: {:stop, :normal, socket}
  end
end

defmodule Brando.LivePreviewChannel do
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
    with :ok <- Preview.authorize(preview_id, socket.assigns.user_id) do
      Realtime.subscribe()
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

  def handle_info({:authorization_changed, _}, socket) do
    if Preview.authorize(socket.assigns.preview_id, socket.assigns.user_id) == :ok,
      do: {:noreply, socket},
      else: {:stop, :normal, socket}
  end
end

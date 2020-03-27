defmodule Brando.LivePreviewChannel do
  @moduledoc """
  Channel for user specific interaction.
  """

  use Phoenix.Channel

  @doc """
  Join user channel for your user
  """
  def join("live_preview:" <> _preview_id, _params, socket) do
    user = Guardian.Phoenix.Socket.current_resource(socket)
    socket = assign(socket, :user_id, user.id)
    {:ok, user.id, socket}
  end
end

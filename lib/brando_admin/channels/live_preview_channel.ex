defmodule Brando.LivePreviewChannel do
  @moduledoc """
  Channel for streaming Live Preview updates
  """
  use Phoenix.Channel

  @doc """
  Join live_preview channel for specific preview key
  """
  def join("live_preview:" <> _preview_id, _params, socket) do
    assigned_user_id = socket.assigns.user_id
    {:ok, assigned_user_id, socket}
  end
end

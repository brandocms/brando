defmodule Brando.UserChannel do
  @moduledoc """
  Channel for user specific interaction.
  """

  use Phoenix.Channel

  intercept([
    "alert",
    "progress_popup",
    "set_progress",
    "increase_progress"
  ])

  @doc """
  Join user channel for your user
  """
  def join("user:" <> user_id, _params, socket) do
    assigned_user_id = socket.assigns.user_id

    vsn =
      Brando.otp_app()
      |> Application.spec(:vsn)
      |> to_string()

    if assigned_user_id == String.to_integer(user_id) do
      {:ok, %{vsn: vsn}, socket}
    else
      :error
    end
  end

  def handle_out("progress_popup", payload, socket) do
    push(socket, "progress_popup", payload)
    {:noreply, socket}
  end

  def handle_out("alert", payload, socket) do
    push(socket, "alert", payload)
    {:noreply, socket}
  end

  def handle_out("set_progress", payload, socket) do
    push(socket, "set_progress", payload)
    {:noreply, socket}
  end

  def handle_out("increase_progress", payload, socket) do
    push(socket, "increase_progress", payload)
    {:noreply, socket}
  end

  def handle_info({:user_update, _usr}, socket) do
    {:noreply, socket}
  end

  def alert(user, message) do
    Brando.endpoint().broadcast!("user:" <> Integer.to_string(user.id), "alert", %{
      message: message
    })
  end

  def set_progress(user, value) do
    Brando.endpoint().broadcast!("user:" <> Integer.to_string(user.id), "set_progress", %{
      value: value
    })
  end

  def increase_progress(user, value) do
    Brando.endpoint().broadcast!("user:" <> Integer.to_string(user.id), "increase_progress", %{
      value: value
    })
  end
end

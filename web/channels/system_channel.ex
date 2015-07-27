defmodule Brando.SystemChannel do
  @moduledoc """
  Channel for system information.
  """
  use Phoenix.Channel

  intercept ["log_msg"]

  @interval 1000

  def join("system:stream", _auth_msg, socket) do
    {:ok, socket}
  end
  def join("system:" <> _private_room_id, _auth_msg, _socket) do
    :ignore
  end

  def handle_out("log_msg", payload, socket) do
    push socket, "log_msg", payload
    {:noreply, socket}
  end

  @doc """
  Logs when `user` performs a successful login
  """
  def log(:logged_in, user) do
    body = "#{user.full_name} logget inn"
    do_log(:notice, "fa-info-circle", body)
  end

  @doc """
  Logs when `user` performs a successful logout
  """
  def log(:logged_out, user) do
    body = "#{user.full_name} logget ut"
    do_log(:notice, "fa-info-circle", body)
  end

  @doc """
  Logs system error
  """
  def log(:error, message) do
    do_log(:error, "fa-times-circle", message)
  end

  @doc """
  Logs system info
  """
  def log(:info, message) do
    do_log(:info, "fa-info-circle", message)
  end

  defp do_log(level, icon, body) do
    unless Brando.config(:logging)[:disable_logging] do
      Brando.get_endpoint.broadcast!("system:stream", "log_msg",
                                    %{level: level, icon: icon, body: body})
    end
  end
end
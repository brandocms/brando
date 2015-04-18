defmodule Brando.AdminChannel do
  use Phoenix.Channel

  def join("admin:stream", auth_msg, socket) do
    {:ok, socket}
  end
  def join("admin:" <> _private_room_id, _auth_msg, socket) do
    :ignore
  end

  def handle_out("log_msg", payload, socket) do
    push socket, "log_msg", payload
    {:noreply, socket}
  end

  def log(:logged_in, user) do
    body = "#{user.full_name} logget inn"
    do_log(:notice, "fa-info-circle", body)
  end

  def log(:logged_out, user) do
    body = "#{user.full_name} logget ut"
    do_log(:notice, "fa-info-circle", body)
  end

  defp do_log(level, icon, body) do
    Brando.get_endpoint.broadcast!("admin:stream", "log_msg",
                                   %{level: level, icon: icon, body: body})
  end
end
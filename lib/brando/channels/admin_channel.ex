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

  def test do
    Brando.get_endpoint.broadcast!("admin:stream",
                                   "log_msg",
                                   %{level: :notice,
                                     icon: "fa-info-circle",
                                     body: "Dette er en logg melding."})
    Brando.get_endpoint.broadcast!("admin:stream",
                                   "log_msg",
                                   %{level: :notice,
                                     icon: "fa-info-circle",
                                     body: "Dette er en ny og lengre melding som kan vise hva som skjer når vi får linjeskift."})
  end

end
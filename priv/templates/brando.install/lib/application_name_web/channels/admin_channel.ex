defmodule <%= application_module %>.AdminChannel do
  @moduledoc """
  Administration control channel
  """

  use Phoenix.Channel
  use Brando.Mixin.Channels.PresenceMixin,
    presence_module: <%= application_module %>.Presence

  # def handle_in("domain:action", %{"params" => params}, socket) do
  #   {:reply, {:ok, %{code: 200, params: params}}, socket}
  # end
end

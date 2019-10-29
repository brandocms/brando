defmodule <%= application_module %>.AdminChannel do
  @moduledoc """
  Administration control channel
  """

  use Phoenix.Channel
  use Brando.Mixin.Channels.AdminChannelMixin

  # def handle_in("domain:action", %{"params" => params}, socket) do
  #   {:reply, {:ok, %{code: 200, params: params}}, socket}
  # end
end

defmodule Brando.Mixin.Channels.PresenceMixin do
  @moduledoc """
  Adds presence list to admin channel.

  ### Usage

  ```elixir
  use Brando.Mixin.Channels.PresenceMixin,
    presence_module: MyApp.Presence
  ```
  """
  defmacro __using__(opts) do
    presence_module = Keyword.fetch!(opts, :presence_module)
    quote(generated: true) do
      def handle_in("admin:list_presence", _, socket) do
        {:ok, _} =
          unquote(presence_module).track(socket, socket.assigns.user_id, %{
            online_at: inspect(System.system_time(:seconds))
          })

        push socket, "admin:presence_state", unquote(presence_module).list(socket)

        {:noreply, socket}
      end
    end
  end
end
defmodule Brando.Mixin.Channels.AdminChannelMixin do
  defmacro __using__(_) do
    quote do
      @doc """
      Join admin channel
      """
      def join("admin", _params, socket) do
        user = Guardian.Phoenix.Socket.current_resource(socket)
        socket = assign(socket, :user_id, user.id)
        {:ok, user.id, socket}
      end
      def handle_in("images:delete_images", %{"ids" => ids}, socket) do
        Brando.Images.delete_images(ids)
        {:reply, {:ok, %{code: 200, ids: ids}}, socket}
      end
    end
  end
end

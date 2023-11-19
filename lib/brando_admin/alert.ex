defmodule BrandoAdmin.Alert do
  defmacro __using__(_) do
    quote do
      def handle_info({:alert, message}, %{assigns: %{current_user: current_user}} = socket) do
        BrandoAdmin.Alert.send_to(current_user, message)
        {:noreply, socket}
      end
    end
  end

  def send_to(user, message, opts \\ %{}) do
    Brando.endpoint().broadcast("user:#{user.id}", "alert", Map.merge(%{payload: message}, opts))
  end
end

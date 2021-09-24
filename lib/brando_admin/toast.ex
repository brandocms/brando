defmodule BrandoAdmin.Toast do
  defmacro __using__(_) do
    quote do
      def handle_info({:toast, message}, %{assigns: %{current_user: current_user}} = socket) do
        BrandoAdmin.Toast.send_to(current_user, message)
        {:noreply, socket}
      end
    end
  end

  def send(payload, %{type: :mutation} = opts \\ %{type: :notification, level: :success}) do
    Brando.endpoint().broadcast("lobby", "toast", Map.merge(%{payload: payload}, opts))
  end

  def send_to(user, message, opts \\ %{level: :success, type: :notification})

  def send_to(user, message, opts) do
    Brando.endpoint().broadcast("user:#{user.id}", "toast", Map.merge(%{payload: message}, opts))
  end
end

defmodule BrandoAdmin.ProgressPopup do
  @moduledoc false
  defmacro __using__(_) do
    quote do
      def handle_info({:progress_popup, message}, %{assigns: %{current_user: current_user}} = socket) do
        BrandoAdmin.ProgressPopup.send_to(current_user, message)
        {:noreply, socket}
      end
    end
  end

  def send_to(user, message, opts \\ %{}) do
    Brando.endpoint().broadcast(
      "user:#{user.id}",
      "progress_popup",
      Map.merge(%{payload: message}, opts)
    )
  end
end

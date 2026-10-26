defmodule BrandoAdmin.Alert do
  @moduledoc """
  Alerts in the admin.

  A `b:alert` event (`push_event(socket, "b:alert", %{title: ..., message: ..., type: ...})`)
  opens a dialog. `title` and `message` are text: names, filenames and titles
  other admins control show as written. An alert that needs markup, such as a
  link, sends `html` instead of `message`, built with `escape/1` around every
  value it interpolates.
  """
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

  @doc """
  `value` HTML-escaped, for interpolating into an alert's `html`.
  """
  @spec escape(term()) :: String.t()
  def escape(value), do: value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end

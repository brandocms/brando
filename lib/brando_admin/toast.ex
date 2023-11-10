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
    schema = payload.identifier.schema

    translated_type =
      Brando.Utils.try_path(schema.__translations__(), [:naming, :singular]) ||
        schema.__naming__().singular

    identifier_with_type =
      payload.identifier
      |> Brando.Utils.map_from_struct()
      |> Map.put(:type, translated_type)

    payload = put_in(payload, [:identifier], identifier_with_type)

    map = Map.merge(%{payload: payload}, opts)
    Brando.endpoint().broadcast("lobby", "toast", map)
  end

  def send_to(user, message, opts \\ %{level: :success, type: :notification})

  def send_to(user, message, opts) do
    Brando.endpoint().broadcast("user:#{user.id}", "toast", Map.merge(%{payload: message}, opts))
  end
end

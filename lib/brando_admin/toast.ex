defmodule BrandoAdmin.Toast do
  @topic "b:toast"

  defmacro __using__(_) do
    quote do
      def handle_info({:toast, data}, socket) do
        {:noreply, push_event(socket, "b_toast", data)}
      end
    end
  end

  def send(payload, opts \\ [type: :notification, level: :success]) do
    Phoenix.PubSub.broadcast(
      Brando.pubsub(),
      @topic,
      {:toast,
       %{type: Keyword.get(opts, :type), level: Keyword.get(opts, :level), payload: payload}}
    )
  end
end

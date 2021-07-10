defmodule BrandoAdmin.Toast do
  @topic "b:toast"

  defmacro __using__(_) do
    quote do
      def handle_info({:toast, data}, socket) do
        {:noreply, push_event(socket, "b:toast", data)}
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

  def send_delayed(payload, opts \\ [type: :notification, level: :success]) do
    Task.start(fn ->
      :timer.sleep(500)

      Phoenix.PubSub.broadcast(
        Brando.pubsub(),
        @topic,
        {:toast,
         %{type: Keyword.get(opts, :type), level: Keyword.get(opts, :level), payload: payload}}
      )
    end)
  end
end

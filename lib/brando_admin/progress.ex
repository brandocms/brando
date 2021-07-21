defmodule BrandoAdmin.Progress do
  @moduledoc """
  Progress sent through user channel
  """
  @topic "b:progress"

  defmacro __using__(_) do
    quote do
      def handle_info({:progress, :update, data}, socket) do
        {:noreply, push_event(socket, "b:progress", %{action: :update, data: data})}
      end

      def handle_info({:progress, :show, data}, socket) do
        {:noreply, push_event(socket, "b:progress", %{action: :show, data: data})}
      end

      def handle_info({:progress, :hide, data}, socket) do
        {:noreply, push_event(socket, "b:progress", %{action: :hide, data: data})}
      end
    end
  end

  def show(user) do
    Phoenix.PubSub.broadcast(
      Brando.pubsub(),
      "#{@topic}:#{user.id}",
      {:progress, :show, %{}}
    )
  end

  def hide(user) do
    Phoenix.PubSub.broadcast(
      Brando.pubsub(),
      "#{@topic}:#{user.id}",
      {:progress, :hide, %{}}
    )
  end

  def update(user, status, opts) do
    payload = %{
      status: status,
      percent: Keyword.get(opts, :percent, nil),
      key: Keyword.get(opts, :key, nil)
    }

    Phoenix.PubSub.broadcast(
      Brando.pubsub(),
      "#{@topic}:#{user.id}",
      {:progress, :update, payload}
    )
  end

  def update_delayed(status, opts) do
    payload = %{
      status: status,
      percent: Keyword.get(opts, :percent, nil),
      key: Keyword.get(opts, :key, nil)
    }

    Task.start(fn ->
      :timer.sleep(500)

      Phoenix.PubSub.broadcast(
        Brando.pubsub(),
        @topic,
        {:progress, :update, payload}
      )
    end)
  end
end

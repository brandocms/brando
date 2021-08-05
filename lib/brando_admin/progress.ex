defmodule BrandoAdmin.Progress do
  @moduledoc """
  Progress sent through user channel
  """
  @topic "b:progress"

  defmacro __using__(_) do
    quote do
      def handle_info({:progress, :update, user_id, data}, socket) do
        {:noreply, push_event(socket, "b:progress:#{user_id}", %{action: :update, data: data})}
      end

      def handle_info({:progress, :show, user_id, data}, socket) do
        {:noreply, push_event(socket, "b:progress:#{user_id}", %{action: :show, data: data})}
      end

      def handle_info({:progress, :hide, user_id, data}, socket) do
        {:noreply, push_event(socket, "b:progress:#{user_id}", %{action: :hide, data: data})}
      end
    end
  end

  @spec show(atom | %{:id => any, optional(any) => any}) :: :ok | {:error, any}
  def show(:system), do: nil

  def show(%Brando.Users.User{} = user) do
    Phoenix.PubSub.broadcast(
      Brando.pubsub(),
      @topic,
      {:progress, :show, user.id, %{}}
    )
  end

  def hide(:system), do: nil

  def hide(%Brando.Users.User{} = user) do
    Phoenix.PubSub.broadcast(
      Brando.pubsub(),
      @topic,
      {:progress, :hide, user.id, %{}}
    )
  end

  def update(:system, _, _), do: nil

  def update(%Brando.Users.User{} = user, status, opts) do
    payload = %{
      status: status,
      percent: Keyword.get(opts, :percent, nil),
      key: Keyword.get(opts, :key, nil)
    }

    Phoenix.PubSub.broadcast(
      Brando.pubsub(),
      @topic,
      {:progress, :update, user.id, payload}
    )
  end

  def update_delayed(:system, _, _), do: nil

  def update_delayed(%Brando.Users.User{} = user, status, opts) do
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
        {:progress, :update, user.id, payload}
      )
    end)
  end
end

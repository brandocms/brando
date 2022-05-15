defmodule BrandoAdmin.Presence do
  defmacro __using__(opts) do
    otp_app = Keyword.fetch!(opts, :otp_app)
    pubsub_server = Keyword.fetch!(opts, :pubsub_server)
    presence = Keyword.fetch!(opts, :presence)

    quote do
      use Phoenix.Presence,
        otp_app: unquote(otp_app),
        pubsub_server: unquote(pubsub_server),
        presence: unquote(presence)

      def __brando_presence__, do: true

      def init(_opts) do
        {:ok, %{}}
      end

      def handle_metas(topic, %{joins: joins, leaves: leaves}, presences, state) do
        for {user_id, presence} <- joins do
          user_data = %{user: presence.user, metas: Map.fetch!(presences, user_id)}
          local_broadcast(topic, {__MODULE__, %{user_joined: user_data}})
        end

        for {user_id, presence} <- leaves do
          metas =
            case Map.fetch(presences, user_id) do
              {:ok, presence_metas} -> presence_metas
              :error -> []
            end

          user_data = %{user: presence.user, metas: metas}

          local_broadcast(topic, {__MODULE__, %{user_left: user_data}})
        end

        {:ok, state}
      end

      def track_user(current_user_id) do
        track(
          self(),
          "users",
          current_user_id,
          %{}
        )
      end

      def untrack_user(current_user_id) do
        untrack(
          self(),
          "users",
          current_user_id
        )
      end
    end
  end
end

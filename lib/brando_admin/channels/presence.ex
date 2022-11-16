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
      def init(_opts), do: {:ok, %{}}
      def fetch("lobby", presences), do: presences

      def fetch("url:" <> _rest = topic, presences) do
        users =
          presences
          |> Map.keys()
          |> Brando.Users.get_users_map()
          |> Enum.into(%{})

        for {key, %{metas: metas}} <- presences, into: %{} do
          {key, %{metas: metas, user: users[String.to_integer(key)]}}
        end
      end

      def handle_metas("url:" <> _rest = topic, %{joins: joins, leaves: leaves}, presences, state) do
        for {user_id, presence} <- joins do
          user_data = %{user: presence.user, metas: Map.fetch!(presences, user_id)}

          Phoenix.PubSub.local_broadcast(
            unquote(pubsub_server),
            topic,
            {__MODULE__, {:uri_presence, %{user_joined: user_data}}}
          )
        end

        for {user_id, presence} <- leaves do
          metas =
            case Map.fetch(presences, user_id) do
              {:ok, presence_metas} -> presence_metas
              :error -> []
            end

          user_data = %{user: presence.user, metas: metas}

          Phoenix.PubSub.local_broadcast(
            unquote(pubsub_server),
            topic,
            {__MODULE__, {:uri_presence, %{user_left: user_data}}}
          )
        end

        {:ok, state}
      end

      def handle_metas("lobby", _diff, _presences, state) do
        # TODO: Handle lobby metas here when we dump the JS presence stuff
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

      def track_url(url, current_user_id) do
        timestamp =
          DateTime.utc_now()
          |> DateTime.to_unix()
          |> to_string()

        track(
          self(),
          "url:#{url}",
          current_user_id,
          %{
            last_active: timestamp,
            active_field: nil,
            dirty_fields: []
          }
        )
      end

      def untrack_url(url, current_user_id) do
        untrack(
          self(),
          "url:#{url}",
          current_user_id
        )
      end

      def update_dirty_fields(url, user_id, dirty_fields) do
        update(self(), "url:#{url}", user_id, fn state ->
          %{state | dirty_fields: dirty_fields}
        end)
      end
    end
  end
end

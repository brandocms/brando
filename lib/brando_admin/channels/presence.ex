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

      def fetch("lobby", presences) do
        users =
          presences
          |> Map.keys()
          |> Brando.Users.get_users_map()
          |> Enum.into(%{})

        for {id, %{metas: metas}} <- presences, into: %{} do
          user = users[String.to_integer(id)]

          {user.id,
           %{
             user: %{
               id: user.id,
               name: user.name,
               avatar: user.avatar
             },
             metas: metas
           }}
        end
      end

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

      def handle_metas("lobby", %{joins: joins, leaves: leaves}, presences, state) do
        for {user_id, presence} <- joins do
          metas = Map.fetch!(presences, user_id)

          user_data = %{
            user: %{
              id: presence.user.id,
              name: presence.user.name,
              avatar: presence.user.avatar
            },
            metas: metas
          }

          Phoenix.PubSub.local_broadcast(
            unquote(pubsub_server),
            "presence",
            {__MODULE__, {:presence, %{user_joined: user_data}}}
          )
        end

        for {user_id, presence} <- leaves do
          metas =
            case Map.fetch(presences, user_id) do
              {:ok, presence_metas} -> presence_metas
              :error -> []
            end

          user_data = %{
            user: %{
              id: presence.user.id,
              name: presence.user.name,
              avatar: presence.user.avatar
            },
            metas: metas
          }

          Phoenix.PubSub.local_broadcast(
            unquote(pubsub_server),
            "presence",
            {__MODULE__, {:presence, %{user_left: user_data}}}
          )
        end

        {:ok, state}
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

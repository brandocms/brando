defmodule BrandoAdmin.Presence do
  @moduledoc false

  defmodule LobbyFetcher do
    @moduledoc false

    def fetch(presences) do
      users =
        presences
        |> Map.keys()
        |> Brando.Users.get_users_map()
        |> Map.new()

      for {id, %{metas: metas}} <- presences, into: %{} do
        user = users[String.to_integer(id)]

        {user.id,
         %{
           user: %{
             id: user.id,
             name: user.name,
             avatar: user.avatar,
             last_login: user.last_login
           },
           metas: metas
         }}
      end
    end

    def handle_metas(joins, leaves, presences, pubsub_server) do
      # Process joins
      for {user_id, presence} <- joins do
        metas = Map.fetch!(presences, user_id)

        user_data = %{
          user: %{
            id: presence.user.id,
            name: presence.user.name,
            avatar: presence.user.avatar,
            last_login: presence.user.last_login
          },
          metas: metas
        }

        Phoenix.PubSub.local_broadcast(
          pubsub_server,
          "presence",
          {BrandoAdmin.Presence, {:presence, %{user_joined: user_data}}}
        )
      end

      # Process leaves
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
            avatar: presence.user.avatar,
            last_login: presence.user.last_login
          },
          metas: metas
        }

        Phoenix.PubSub.local_broadcast(
          pubsub_server,
          "presence",
          {BrandoAdmin.Presence, {:presence, %{user_left: user_data}}}
        )
      end
    end
  end

  defmodule UrlFetcher do
    @moduledoc false

    def fetch(presences) do
      users =
        presences
        |> Map.keys()
        |> Brando.Users.get_users_map()
        |> Map.new()

      for {key, %{metas: metas}} <- presences, into: %{} do
        {key, %{metas: metas, user: users[String.to_integer(key)]}}
      end
    end

    def handle_metas(topic, joins, leaves, presences, pubsub_server) do
      # Process joins
      for {user_id, presence} <- joins do
        user_data = %{user: presence.user, metas: Map.fetch!(presences, user_id)}

        Phoenix.PubSub.local_broadcast(
          pubsub_server,
          topic,
          {BrandoAdmin.Presence, {:uri_presence, %{user_joined: user_data}}}
        )
      end

      # Process leaves
      for {user_id, presence} <- leaves do
        metas =
          case Map.fetch(presences, user_id) do
            {:ok, presence_metas} -> presence_metas
            :error -> []
          end

        user_data = %{user: presence.user, metas: metas}

        Phoenix.PubSub.local_broadcast(
          pubsub_server,
          topic,
          {BrandoAdmin.Presence, {:uri_presence, %{user_left: user_data}}}
        )
      end
    end
  end

  @doc false
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

      # Implementations moved to external modules
      def fetch("lobby", presences), do: BrandoAdmin.Presence.LobbyFetcher.fetch(presences)
      def fetch("url:" <> _rest = _topic, presences), do: BrandoAdmin.Presence.UrlFetcher.fetch(presences)

      def handle_metas("lobby", %{joins: joins, leaves: leaves}, presences, state) do
        BrandoAdmin.Presence.LobbyFetcher.handle_metas(joins, leaves, presences, unquote(pubsub_server))
        {:ok, state}
      end

      def handle_metas("url:" <> _rest = topic, %{joins: joins, leaves: leaves}, presences, state) do
        BrandoAdmin.Presence.UrlFetcher.handle_metas(topic, joins, leaves, presences, unquote(pubsub_server))
        {:ok, state}
      end

      # URL tracking functions
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

      def update_active_field(url, user_id, active_field) do
        update(self(), "url:#{url}", user_id, fn state ->
          %{state | active_field: active_field}
        end)
      end
    end
  end
end

defmodule BrandoAdmin.Presence do
  @moduledoc false

  require Logger

  @doc """
  The browser tab this process serves. An admin LiveView and its components
  run in one process per tab (a reconnect is a new process, so a new tab),
  and entry field locks belong to a tab, not to its user: one user can have
  the entry open in two tabs, in two fields.
  """
  def tab do
    self()
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> binary_part(0, 12)
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Tells the other editors of an entry which field this tab is in (an input
  name, `page[title]`), or that it left it (`nil`), which releases the field.
  """
  def broadcast_active_field(schema, entry_id, field, user_id) do
    Phoenix.PubSub.broadcast(
      Brando.pubsub(),
      Brando.Tenant.Topic.entry("active_field", schema, entry_id),
      {:active_field, field, user_id, tab()}
    )
  end

  @doc false
  # The users behind `presences`, by id. `Phoenix.Presence` runs `fetch/2` for
  # each diff in a task the presence shard monitors, and has no clause for one
  # that dies: a lookup that raised or exited there took the shard down, and
  # every admin session tracked on it. Without the users, the presences are
  # left out (lobby) or carry no user (url), as for a deleted account, and the
  # next diff brings them back.
  def users(presences) do
    presences
    |> Map.keys()
    |> Brando.Users.get_users_map()
    |> Map.new()
  rescue
    exception ->
      Logger.error("==> Presence: could not look up users: " <> Exception.message(exception))
      %{}
  catch
    # A pool checkout that fails exits: a connection timeout in production,
    # or in tests a sandbox owner that has gone
    :exit, reason ->
      Logger.error("==> Presence: could not look up users: " <> Exception.format_exit(reason))
      %{}
  end

  defmodule LobbyFetcher do
    @moduledoc false

    require Logger

    def fetch(presences) do
      users = BrandoAdmin.Presence.users(presences)

      for {id, %{metas: metas}} <- presences,
          user = users[String.to_integer(id)],
          not is_nil(user),
          into: %{} do
        {user.id,
         %{
           user: %{
             id: user.id,
             name: user.name,
             avatar: user.avatar,
             last_login: user.last_login,
             last_seen: user.last_seen
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
            last_login: presence.user.last_login,
            last_seen: presence.user.last_seen
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

        # No metas left means this was the user's last admin session, so this is
        # the moment they were last here.
        if metas == [], do: record_last_seen(presence.user.id)

        user_data = %{
          user: %{
            id: presence.user.id,
            name: presence.user.name,
            avatar: presence.user.avatar,
            last_login: presence.user.last_login,
            last_seen: presence.user.last_seen
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

    # Recording the departure here, rather than in a subscriber, is the whole
    # point. `BrandoAdmin.Chrome` is the only subscriber to "presence" and it is
    # a sticky LiveView — one per open admin browser — and it used to own this
    # write. So a user's "last seen" was recorded by *other people's* browsers:
    # when the last admin left, the broadcast went out and the only process that
    # would have persisted it was the one dying. Someone working alone never had
    # a departure recorded at all, and their timestamp sat at whatever it was the
    # last time a colleague happened to be online to witness them leaving.
    # Reported from production as a user's last-seen frozen twelve days back,
    # on a site with two editors who rarely overlap.
    #
    # `handle_metas/4` runs in the presence process for every leave, watchers or
    # not, which is the property the write needs. It is also the only place that
    # sees a leave exactly once, so the redundant write every online browser used
    # to perform goes away with it.
    defp record_last_seen(user_id) do
      Brando.Users.set_last_seen(%Brando.Users.User{id: user_id})
      :ok
    rescue
      exception ->
        # A raise here would take the tracker down and presence with it, for
        # everyone connected — a missed timestamp is much the smaller loss.
        #
        # Synchronous and unspawned on purpose: leaves are rare, the write is a
        # single UPDATE by primary key, and spawning would let a quick
        # leave/rejoin/leave land its writes out of order and record the older
        # time as the newer one.
        Logger.error(
          "==> Presence: could not record last seen for user #{inspect(user_id)}: " <>
            Exception.message(exception)
        )

        :ok
    catch
      # A pool checkout that fails exits rather than raises: a connection
      # timeout in production, or in tests the owner of a sandboxed
      # connection that has already gone when the leave arrives. The same
      # reasoning applies; it must not take the tracker down.
      :exit, reason ->
        Logger.error(
          "==> Presence: could not record last seen for user #{inspect(user_id)}: " <>
            Exception.format_exit(reason)
        )

        :ok
    end
  end

  defmodule UrlFetcher do
    @moduledoc false

    def fetch(presences) do
      users = BrandoAdmin.Presence.users(presences)

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

        # `metas` are the user's sessions still here, `left` the ones that
        # went. An update of a meta is a leave and a join of the same tab.
        # `user_id` is the presence key: `user` is nil for an account that
        # no longer loads (deleted), whose field locks still go by its id.
        user_data = %{
          user: presence.user,
          user_id: String.to_integer(user_id),
          metas: metas,
          left: Map.get(presence, :metas, [])
        }

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
      # `meta` adds to the defaults; the frontend editor tracks itself under
      # the entry's admin URL with `%{frontend: true}`.
      def track_url(url, current_user_id, meta \\ %{}) do
        timestamp =
          DateTime.utc_now()
          |> DateTime.to_unix()
          |> to_string()

        track(
          self(),
          Brando.Tenant.Topic.scoped("url:#{url}"),
          current_user_id,
          Map.merge(
            %{
              last_active: timestamp,
              active_field: nil,
              dirty_fields: [],
              tab: BrandoAdmin.Presence.tab()
            },
            meta
          )
        )
      end

      def untrack_url(url, current_user_id) do
        untrack(
          self(),
          Brando.Tenant.Topic.scoped("url:#{url}"),
          current_user_id
        )
      end

      def update_dirty_fields(url, user_id, dirty_fields) do
        update(self(), Brando.Tenant.Topic.scoped("url:#{url}"), user_id, fn state ->
          %{state | dirty_fields: dirty_fields}
        end)
      end

      def update_active_field(url, user_id, active_field) do
        update(self(), Brando.Tenant.Topic.scoped("url:#{url}"), user_id, fn state ->
          %{state | active_field: active_field}
        end)
      end
    end
  end
end

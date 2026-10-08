defmodule Brando.Users.SecurityLog do
  @moduledoc """
  The log of sign-in security events (`Brando.Users.SecurityEvent`):
  sign-ins, failed sign-ins and lockouts, and changes to passwords and
  two-factor settings, with the IP address and browser they came from.

  Users are shared by every site, so the log lives in `public`, apart from the
  content activity log (`Brando.Activity`). It keeps events as long as that
  one does (`Brando.Activity.retention_days/0`), and the user's security page
  and an administrator's view of the user form show the latest.

  Recording never fails the action it records: an event that cannot be
  written is logged and dropped.

  Everyone's events are listed in Configuration → Activity → Security for
  those `readable_by?/1` allows.
  """

  import Ecto.Query

  alias Brando.Authorization
  alias Brando.Authorization.{Engine, Scope}
  alias Brando.Repo
  alias Brando.Users.SecurityEvent
  alias Phoenix.LiveView

  require Logger

  @type meta :: %{optional(:ip) => String.t() | nil, optional(:user_agent) => String.t() | nil}

  @doc """
  Records `action` for `user` (a user, a user id or nil). Options:

    * `:actor` — who did it, when not the user themselves;
    * `:meta` — `%{ip:, user_agent:}` of the request, see `meta/1`;
    * `:details` — a map of facts about the event.
  """
  @spec record(atom(), map() | integer() | nil, keyword()) :: :ok
  def record(action, user, opts \\ []) do
    meta = Keyword.get(opts, :meta) || %{}

    attrs = %{
      action: action,
      user_id: id(user),
      actor_id: id(Keyword.get(opts, :actor)),
      ip: meta[:ip],
      user_agent: meta[:user_agent] && String.slice(meta[:user_agent], 0, 255),
      details: Keyword.get(opts, :details, %{})
    }

    insert_opts = if Repo.repo().in_transaction?(), do: [mode: :savepoint], else: []

    case %SecurityEvent{} |> Ecto.Changeset.change(attrs) |> Repo.insert(insert_opts) do
      {:ok, _event} -> :ok
      {:error, changeset} -> warn(inspect(changeset.errors))
    end
  rescue
    error -> warn(Exception.message(error))
  end

  defp warn(message) do
    Logger.warning("[Brando.Users.SecurityLog] Could not record a security event: " <> message)
    :ok
  end

  defp id(%{id: id}), do: id
  defp id(id) when is_integer(id), do: id
  defp id(_), do: nil

  @doc """
  The IP address and browser of a request, from a `Plug.Conn`, or from the
  `:peer_data`, `:x_headers` and `:user_agent` of a LiveView's connect info.
  The address is the client's behind a trusted proxy (`Brando.ClientIP`).
  """
  @spec meta(Plug.Conn.t() | map()) :: meta()
  def meta(%Plug.Conn{} = conn) do
    %{
      ip: ip_string(Brando.ClientIP.from_conn(conn)),
      user_agent: conn |> Plug.Conn.get_req_header("user-agent") |> List.first()
    }
  end

  def meta(%{} = info) do
    %{ip: ip_string(Brando.ClientIP.from_connect_info(info)), user_agent: info[:user_agent]}
  end

  @doc """
  `meta/1` of a connected LiveView socket, or nil before it connects. The
  socket's `connect_info` should give `:peer_data`, `:x_headers` and
  `:user_agent`; without them there is no address, and limits per IP
  address do not apply.
  """
  @spec socket_meta(Phoenix.LiveView.Socket.t()) :: meta() | nil
  def socket_meta(socket) do
    if LiveView.connected?(socket) do
      meta(%{
        peer_data: LiveView.get_connect_info(socket, :peer_data),
        x_headers: LiveView.get_connect_info(socket, :x_headers),
        user_agent: LiveView.get_connect_info(socket, :user_agent)
      })
    end
  end

  defp ip_string(nil), do: nil
  defp ip_string(address), do: address |> :inet.ntoa() |> to_string()

  @doc "The latest `limit` events of `user`, with whoever else acted."
  @spec list(map(), pos_integer()) :: [SecurityEvent.t()]
  def list(%{id: user_id}, limit \\ 10) do
    from(e in SecurityEvent,
      where: e.user_id == ^user_id,
      order_by: [desc: e.inserted_at, desc: e.id],
      limit: ^limit,
      preload: [:actor]
    )
    |> Repo.all()
  end

  @doc """
  Whether `user` may see every user's events (Configuration → Activity →
  Security). Each user sees their own on their security page regardless.

  Users are shared by every site, and their events say nothing about which
  site they worked on. With several sites (`Brando.Tenant.mode/0` is
  `:multi`) only superusers see them, since an administrator of one site
  would otherwise follow the sign-ins of people who work on other sites.
  With one site: administrators and superusers, or with group authorization
  the `brando.security_log.read` permission in the current scope.
  """
  @spec readable_by?(map() | nil) :: boolean()
  def readable_by?(%{id: id} = user) when is_integer(id) do
    multi? = Brando.Tenant.mode() == :multi

    cond do
      Authorization.enabled?() and multi? -> Engine.superuser?(Scope.installation(user))
      Authorization.enabled?() -> Authorization.can?(Scope.current(user), :read, :security_log)
      multi? -> Map.get(user, :role) == :superuser
      true -> Map.get(user, :role) in [:admin, :superuser]
    end
  end

  def readable_by?(_user), do: false

  @doc """
  Everyone's events matching `filters`, newest first, with the user and
  whoever else acted. Filters: `:user_id`, `:action` and `:since` (a
  `DateTime`); nil leaves one out. Options: `:limit` (50) and `:offset`.
  Only for those `readable_by?/1` allows.
  """
  @spec list_all(map(), keyword()) :: [SecurityEvent.t()]
  def list_all(filters \\ %{}, opts \\ []) do
    filters
    |> filtered()
    |> order_by([e], desc: e.inserted_at, desc: e.id)
    |> limit(^Keyword.get(opts, :limit, 50))
    |> offset(^Keyword.get(opts, :offset, 0))
    |> preload([:actor, user: :avatar])
    |> Repo.all()
  end

  @doc "How many events match `filters` (see `list_all/2`)."
  @spec count_all(map()) :: non_neg_integer()
  def count_all(filters \\ %{}), do: filters |> filtered() |> Repo.aggregate(:count)

  defp filtered(filters) do
    Enum.reduce(filters, from(e in SecurityEvent), fn
      {_key, nil}, query -> query
      {:user_id, id}, query -> where(query, [e], e.user_id == ^id)
      {:action, action}, query -> where(query, [e], e.action == ^action)
      {:since, since}, query -> where(query, [e], e.inserted_at >= ^since)
      _, query -> query
    end)
  end

  @doc "The users who have events, by name, for filtering."
  @spec users() :: [Brando.Users.User.t()]
  def users do
    from(u in Brando.Users.User,
      where: u.id in subquery(from(e in SecurityEvent, where: not is_nil(e.user_id), distinct: true, select: e.user_id)),
      order_by: u.name
    )
    |> Repo.all()
  end

  @doc "Removes events older than `days`. Returns how many."
  @spec purge(pos_integer()) :: non_neg_integer()
  def purge(days \\ Brando.Activity.retention_days()) do
    cutoff = DateTime.add(DateTime.utc_now(), -days * 86_400, :second)
    {count, _} = Repo.delete_all(from(e in SecurityEvent, where: e.inserted_at < ^cutoff))
    count
  end
end

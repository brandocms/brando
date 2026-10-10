defmodule Brando.Notifications.Recipient do
  @moduledoc """
  Who an email route may send to, and whether a notification may still go to
  them when it is sent.

  A recipient is an active account that may enter the current site: with
  group authorization, one with backend access in its scope; with tenancy and
  legacy roles, one assigned to the site (or a superuser); otherwise every
  active account. A notification about an entry also needs read access to it
  (with group authorization). Whatever was queued, it is sent only while its
  route is active, still sends by email and still names the user.

  A check that fails counts as "no", and is logged, except when the database
  failed in a way that may pass (a lost connection, a timeout, a deadlock):
  then it raises, so the job sending the email is retried instead of dropping
  what it sends, unless it is the job's last attempt (`final_attempt/2`).
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.Engine
  alias Brando.Authorization.Scope
  alias Brando.Notifications.Route
  alias Brando.Repo
  alias Brando.Users.User

  require Logger

  @final_attempt {__MODULE__, :final_attempt}

  @doc "The users an email route may send to in the current site environment, by name."
  def options do
    from(u in User, where: u.active == true and is_nil(u.deleted_at), order_by: [asc: u.name, asc: u.id])
    |> Repo.all()
    |> Enum.filter(&member?/1)
    |> Enum.map(&%{id: &1.id, name: &1.name, email: &1.email})
  end

  @doc "Whether `user` may enter the current site (see the moduledoc)."
  def member?(%User{} = user), do: checked(fn -> member_check(user) end)
  def member?(_), do: false

  defp member_check(user) do
    cond do
      Engine.enabled?() -> Engine.can?(Scope.current(user), :access, :backend)
      Brando.Tenant.enabled?() -> site_access?(user)
      true -> true
    end
  end

  defp site_access?(user) do
    case Brando.Tenant.current_site_key() && Brando.Tenant.Registry.get_site_by_key(Brando.Tenant.current_site_key()) do
      nil -> false
      site -> Brando.Tenant.Access.can_access?(user, site)
    end
  end

  @doc """
  Whether the queued `delivery` may still go to `user` on `route`: the route
  is active, sends email and names the user, who is an active member of the
  site and, for an entry, may read it.
  """
  def may_see?(user, delivery, route), do: access(user, delivery, route) == :ok

  @doc "Whether `delivery` may go to `user`, whatever route it came on."
  def may_see?(user, delivery), do: access(user, delivery) == :ok

  @doc """
  As `may_see?/3`, saying why not: `:ok`, `:denied`, or `:unchecked` when
  the check failed and counts as "no" (see the moduledoc).
  """
  def access(user, delivery, %Route{active: true, kind: :email, recipient_ids: ids}) do
    if user.id in ids, do: access(user, delivery), else: :denied
  end

  def access(_user, _delivery, _route), do: :denied

  @doc "As `may_see?/2`, saying why not, as `access/3`."
  def access(%User{active: true, deleted_at: nil} = user, delivery) do
    checked(
      fn -> if member_check(user) and entry_readable?(user, delivery), do: :ok, else: :denied end,
      :unchecked
    )
  end

  def access(_user, _delivery), do: :denied

  # An entry that is gone, or of a schema that is gone, can no longer be
  # read, and is not sent about
  defp entry_readable?(user, %{entry_schema: schema, entry_id: id}) when is_binary(schema) and is_integer(id) do
    with true <- Brando.Authorization.enabled?(),
         {:ok, module} <- entry_schema(schema) do
      case Repo.get(module, id) do
        nil -> false
        entry -> read_check(user, entry)
      end
    else
      false -> true
      :error -> false
    end
  end

  defp entry_readable?(_user, _delivery), do: true

  @doc """
  The Ecto schema an entry type names (`"Elixir.MyApp.Projects.Project"`):
  `{:ok, module}`, or `:error` when no such schema exists (any more).
  """
  def entry_schema(type) when is_binary(type) do
    module = String.to_existing_atom(type)
    if Code.ensure_loaded?(module) and function_exported?(module, :__schema__, 1), do: {:ok, module}, else: :error
  rescue
    ArgumentError -> :error
  end

  @doc """
  Whether `user` may read `entry`: with group authorization, by its read
  permission; otherwise yes. A failed check is handled as the moduledoc says.
  """
  def may_read?(%User{} = user, entry), do: checked(fn -> read_check(user, entry) end)

  defp read_check(user, entry),
    do: not Brando.Authorization.enabled?() or Brando.Authorization.can?(Scope.current(user), :read, entry)

  @doc """
  Runs an access `check`, returning its result. When it raises, returns
  `denied` and logs why, but raises again when the database failed in a way
  that may pass, for the calling job to be retried, unless that job is on
  its last attempt (see the moduledoc).
  """
  def checked(check, denied \\ false) when is_function(check, 0) do
    check.()
  rescue
    error ->
      if transient?(error) and not Process.get(@final_attempt, false), do: reraise(error, __STACKTRACE__)
      Logger.error("[Brando.Notifications] Access check failed, not sending: " <> Exception.message(error))
      denied
  end

  @doc """
  Runs `fun` as the job's last attempt when `final?`: a database failure
  while checking access then counts as "no" instead of raising, so what
  cannot be checked is dropped rather than retried for ever.
  """
  def final_attempt(final?, fun) when is_function(fun, 0) do
    previous = Process.put(@final_attempt, final?)

    try do
      fun.()
    after
      if previous == nil, do: Process.delete(@final_attempt), else: Process.put(@final_attempt, previous)
    end
  end

  @doc """
  Whether `error` is a database failure that may pass when tried again: a
  lost or refused connection, a timeout or cancelled statement, a deadlock or
  serialization failure, a lock not available, too many connections, or a
  server shutting down. A missing table or column, or a bad query, is not.
  """
  def transient?(%DBConnection.ConnectionError{}), do: true
  def transient?(%Postgrex.Error{postgres: %{pg_code: "55P03"}}), do: true

  def transient?(%Postgrex.Error{postgres: %{pg_code: code}}) when is_binary(code),
    do: String.starts_with?(code, ["08", "40", "53", "57", "58"])

  # Failures below the protocol (connection, TLS) carry no SQL state
  def transient?(%Postgrex.Error{postgres: nil}), do: true
  def transient?(_error), do: false
end

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
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.Engine
  alias Brando.Authorization.Scope
  alias Brando.Notifications.Route
  alias Brando.Repo
  alias Brando.Users.User

  @doc "The users an email route may send to in the current site environment, by name."
  def options do
    from(u in User, where: u.active == true and is_nil(u.deleted_at), order_by: [asc: u.name, asc: u.id])
    |> Repo.all()
    |> Enum.filter(&member?/1)
    |> Enum.map(&%{id: &1.id, name: &1.name, email: &1.email})
  end

  @doc """
  Whether `user` may enter the current site (see the moduledoc). A failure
  while checking (the database) raises rather than counting as "no", so a
  job sending email fails and is retried instead of dropping what it sends.
  """
  def member?(%User{} = user) do
    cond do
      Engine.enabled?() -> Engine.can?(Scope.current(user), :access, :backend)
      Brando.Tenant.enabled?() -> site_access?(user)
      true -> true
    end
  end

  def member?(_), do: false

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
  def may_see?(user, delivery, %Route{active: true, kind: :email, recipient_ids: ids}) do
    user.id in ids and may_see?(user, delivery)
  end

  def may_see?(_user, _delivery, _route), do: false

  @doc "Whether `delivery` may go to `user`, whatever route it came on."
  def may_see?(%User{active: true, deleted_at: nil} = user, delivery) do
    member?(user) and entry_readable?(user, delivery)
  end

  def may_see?(_user, _delivery), do: false

  defp entry_readable?(user, %{entry_schema: schema, entry_id: id}) when is_binary(schema) and is_integer(id) do
    if Brando.Authorization.enabled?(), do: readable?(user, schema, id), else: true
  end

  defp entry_readable?(_user, _delivery), do: true

  # An entry that is gone, or of a schema that is gone, can no longer be
  # read, and is not sent about
  defp readable?(user, schema, id) do
    with {:ok, module} <- entry_schema(schema),
         %{} = entry <- Repo.get(module, id) do
      may_read?(user, entry)
    else
      _ -> false
    end
  end

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
  permission; otherwise yes. Like `member?/1`, raises when checking fails.
  """
  def may_read?(%User{} = user, entry) do
    not Brando.Authorization.enabled?() or Brando.Authorization.can?(Scope.current(user), :read, entry)
  end
end

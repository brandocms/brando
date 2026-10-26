defmodule Brando.Authorization.Boundary do
  @moduledoc """
  Authorization at generated context boundaries and scoped admin reads.

  Public frontend queries keep their existing behavior outside an admin scope.
  Context mutations with a user always enforce groups once group mode is enabled.
  `:system` is reserved for explicitly trusted maintenance code.

  ## Two modes

  `config :brando, authorization_mode:` is `:legacy` (the default: the
  application's role rules) or `:groups`. In legacy mode `run/4` calls `fun`
  with no transaction, and checks only what the roles always meant:

    * module and container code (`Brando.Authorization.Catalog.superuser_only?/2`)
      is written by superusers, in both modes;
    * a `:user` account writes nothing but its own profile;
    * only a superuser deactivates or deletes another superuser.

  Changing another user's email or password takes a superuser in both modes
  (`Brando.Trait.ProtectPassword.allowed?/2`): the email is where a password
  reset link goes. Everything else is allowed. A change to group-mode
  behaviour leaves legacy mode as it was unless it means to change it too;
  test both.

  ## `:forbidden`

  `{:error, :forbidden}` is every denial, not only a missing grant: an
  inactive account, an inactive site, a scope that does not match its site,
  environment or subject (`:wrong_scope`), an unknown permission, no backend
  access, a protected account or a resource policy. `Brando.Authorization.explain/3`
  gives the reason. Treat `:forbidden` as "not allowed in this scope", not as
  "lacks the grant".
  """
  alias Brando.Authorization.{Catalog, Engine, Groups, Scope}
  alias Brando.Repo
  alias Brando.Trait.ProtectPassword
  alias Brando.Trait.ProtectRole
  alias Brando.Users.User

  @scope_key {__MODULE__, :scope}
  @presentation_key {__MODULE__, :presentation}
  @query_action_key {__MODULE__, :query_action}

  def current_scope, do: Process.get(@scope_key)
  def put_scope(%Scope{} = scope), do: Process.put(@scope_key, scope)
  def put_scope(nil), do: Process.delete(@scope_key)

  @doc """
  Caches the admin's authorization snapshot for menus and other presentation in this process.

  `presentation/0` only returns it while the same scope is current.
  """
  def put_presentation(snapshot), do: Process.put(@presentation_key, snapshot)

  def presentation do
    case Process.get(@presentation_key) do
      %{scope: scope} = snapshot -> if scope == current_scope(), do: snapshot
      _ -> nil
    end
  end

  @doc "Runs scoped admin reads, restoring the previous process context afterwards."
  def with_scope(scope, fun) do
    previous = current_scope()
    put_scope(scope)

    try do
      fun.()
    after
      put_scope(previous)
    end
  end

  @doc """
  Runs `fun` as a context mutation after checking that `actor` may perform `action` on `schema`.

  With groups enabled the check and `fun` share one transaction inside the actor's scope and
  tenant prefix, and `fun` receives the authorized user. A denied check or an `{:error, reason}`
  from `fun` rolls back and returns `{:error, reason}`. `:system` runs `fun` directly; so does
  legacy mode, after its checks (see the moduledoc), with the user's role read afresh.
  """
  def run(:system, _action, _schema, fun), do: with_scope(nil, fn -> fun.(:system) end)

  def run(actor, action, schema, fun) do
    if Engine.enabled?() do
      run_authorized(actor_scope(actor), action, schema, fun)
    else
      actor = fresh_role(actor)
      with :ok <- legacy_authorize(actor, action, schema), do: fun.(actor)
    end
  end

  defp run_authorized(scope, action, schema, fun) do
    result =
      Repo.transaction(fn ->
        if schema == Brando.Users.User, do: Groups.lock!()
        with_scope(scope, fn -> run_in_scope(scope, action, schema, fun) end)
      end)

    case result do
      {:ok, value} ->
        if schema == Brando.Users.User,
          do: Phoenix.PubSub.broadcast(Brando.pubsub(), "brando:authorization", {:authorization_changed, :all})

        value

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_in_scope(scope, action, schema, fun) do
    snapshot = Engine.snapshot(scope)

    unless run_allowed?(snapshot, action, schema), do: Repo.rollback(:forbidden)

    if scope.kind == :site and schema.__schema__(:prefix) != "public" and not is_binary(scope.prefix),
      do: Repo.rollback(:forbidden)

    result = Brando.Tenant.with_prefix(scope.prefix, fn -> fun.(snapshot.user) end)

    case result do
      {:error, reason} -> Repo.rollback(reason)
      value -> value
    end
  end

  defp run_allowed?(snapshot, action, schema) do
    Engine.can?(snapshot, action, schema) or
      (schema == Brando.Users.User and action == :update and Engine.can?(snapshot, :update, :profile))
  end

  def authorize(:system, _, _), do: :ok

  def authorize(actor, action, subject) do
    if Engine.enabled?(),
      do: Engine.authorize(actor_scope(actor), action, subject),
      else: legacy_authorize(actor, action, subject)
  end

  @doc """
  Whether `actor` is a superuser: in the installation's superuser group with groups
  authorization, of the `:superuser` role without. Only superusers write module and
  container code, and act on another user's credentials. Reads the role afresh.
  """
  def superuser?(:system), do: true

  def superuser?(actor) do
    if Engine.enabled?(),
      do: Engine.superuser?(Scope.installation(%{id: user_id(actor)})),
      else: actor |> fresh_role() |> legacy_role() == :superuser
  end

  def restore(actor, %{__struct__: schema} = entry) do
    run(actor, :restore, schema, fn user ->
      with :ok <- authorize(user, :restore, entry),
           changeset <- Ecto.Changeset.change(entry, deleted_at: nil),
           :ok <- change(user, :update, changeset),
           {:ok, restored} <- Repo.restore(entry) do
        Brando.Activity.restored(restored, user)
        Brando.Notes.entry_restored(schema, entry)
        {:ok, restored}
      end
    end)
  end

  def change(:system, _, _), do: :ok

  def change(actor, action, changeset) do
    if Engine.enabled?() do
      with :ok <- Engine.authorize_change(actor_scope(actor), action, changeset),
           :ok <- protect_credentials(actor, changeset) do
        protect_account(changeset)
      end
    else
      # A changeset built elsewhere may carry the target as it was: its stored role counts.
      changeset = with_stored_role(changeset)

      with :ok <- legacy_authorize(actor, action, changeset.data),
           :ok <- legacy_profile(actor, changeset),
           :ok <- legacy_role_change(actor, changeset),
           :ok <- protect_credentials(actor, changeset) do
        legacy_protect_superuser(actor, changeset)
      end
    end
  end

  def query(query, schema) do
    if Engine.enabled?() and current_scope() do
      action =
        case Process.get(@query_action_key) do
          {action, ^schema} -> action
          _ -> :read
        end

      if schema == Brando.Content.Identifier,
        do: identifiers(query),
        else: Engine.scope_query(current_scope(), action, query, schema)
    else
      query
    end
  end

  def with_query_action(action, schema, fun) do
    previous = Process.get(@query_action_key)
    Process.put(@query_action_key, {action, schema})

    try do
      fun.()
    after
      if previous, do: Process.put(@query_action_key, previous), else: Process.delete(@query_action_key)
    end
  end

  @doc "Applies each source resource's read policy before identifier pagination."
  def identifiers(query) do
    if Engine.enabled?() and current_scope() do
      import Ecto.Query, only: [dynamic: 2, where: 3, from: 2, subquery: 1]
      snapshot = Engine.snapshot(current_scope())

      allowed =
        Brando.Authorization.Catalog.schemas()
        |> Enum.filter(&Engine.can?(snapshot, :read, &1))
        |> Enum.reduce(dynamic([identifier], false), fn schema, allowed ->
          ids = from(entry in Engine.scope(current_scope(), :read, schema), select: entry.id)
          dynamic([identifier], ^allowed or (identifier.schema == ^schema and identifier.entry_id in subquery(ids)))
        end)

      where(query, [identifier], ^allowed)
    else
      query
    end
  end

  def cache_options(args) do
    if Engine.enabled?() and current_scope(), do: Map.delete(args, :cache), else: args
  end

  @doc "Filters metadata queries through the parent resource's read policy."
  def subject_query(query, schema, id, action \\ :read) do
    if Engine.enabled?() and current_scope() do
      import Ecto.Query, only: [from: 2]
      schema = Brando.Authorization.Catalog.schema(schema)

      visible =
        schema && Repo.one(from(e in Engine.scope(current_scope(), action, schema), where: e.id == ^id, select: e.id))

      query = Ecto.Query.put_query_prefix(query, current_scope().prefix || "public")
      if visible, do: query, else: from(q in query, where: false)
    else
      query
    end
  end

  @doc "Checks a concrete record before a custom context operation."
  def authorize_record(:system, _, _, _), do: :ok

  def authorize_record(actor, action, schema, id) do
    if Engine.enabled?() do
      import Ecto.Query, only: [from: 2]
      scope = actor_scope(actor)

      with schema when not is_nil(schema) <- Brando.Authorization.Catalog.schema(schema),
           record when not is_nil(record) <- Repo.one(from(e in Engine.scope(scope, action, schema), where: e.id == ^id)),
           :ok <- Engine.authorize(scope, action, record),
           do: :ok,
           else: (_ -> {:error, :forbidden})
    else
      legacy_authorize(actor, action, schema)
    end
  end

  @doc """
  Checks `action` on the record `id` against the current admin scope.

  Returns `:ok` outside an admin scope, so public callers keep their existing behaviour.
  """
  def admin_record(action, schema, id) do
    if current_scope(), do: authorize_record(current_scope(), action, schema, id), else: :ok
  end

  def actor_scope(%Scope{} = scope), do: scope

  def actor_scope(%{id: id} = actor) do
    case current_scope() do
      %Scope{user_id: ^id} = scope -> scope
      _ -> Scope.current(actor)
    end
  end

  def actor_scope(actor), do: Scope.current(actor)

  defp protect_account(%{data: %{__struct__: Brando.Users.User, id: id}, changes: changes}) when not is_nil(id) do
    if Map.get(changes, :active) == false or Map.get(changes, :deleted_at), do: Groups.protect_account!(id)
    :ok
  end

  defp protect_account(_), do: :ok

  # The email is where a password reset link goes: changing another user's
  # takes the authority changing their password does, in both modes. An
  # invalid changeset is let through to show its own errors; it saves nothing.
  defp protect_credentials(actor, %{data: %User{id: id} = user, changes: changes, valid?: true})
       when not is_nil(id) do
    if (Map.has_key?(changes, :email) or Map.has_key?(changes, :password)) and
         not ProtectPassword.allowed?(actor, user),
       do: {:error, :forbidden},
       else: :ok
  end

  defp protect_credentials(_actor, _changeset), do: :ok

  # The roles' meaning in legacy mode: code is a superuser's, a `:user`
  # account edits nothing, and a superuser is deleted by superusers only. An
  # actor given by id has its stored role. One with no role (nil, as for a
  # scheduled publication whose user is gone) writes all but code, as before.
  # Group mode's `Engine` checks the same on its own terms.
  defp legacy_authorize(:system, _action, _subject), do: :ok

  defp legacy_authorize(actor, action, subject) do
    role = legacy_role(actor)

    cond do
      Catalog.superuser_only?(action, subject) and role != :superuser ->
        {:error, :forbidden}

      role == :user and not user_may?(actor, action, subject) ->
        {:error, :forbidden}

      superuser_deletion?(action, subject) and not ProtectPassword.allowed?(actor, subject) ->
        {:error, :forbidden}

      true ->
        :ok
    end
  end

  defp user_may?(actor, action, subject), do: action in [:read, :export] or own_profile?(actor, action, subject)

  defp superuser_deletion?(:delete, subject), do: superuser_account?(subject)
  defp superuser_deletion?(_action, _subject), do: false

  # The schema itself stands for "some user": `change/3` checks the record.
  defp own_profile?(_actor, :update, User), do: true
  defp own_profile?(actor, :update, %User{id: id}), do: not is_nil(id) and id == user_id(actor)
  defp own_profile?(_actor, _action, _subject), do: false

  @profile_fields [:name, :email, :password, :language, :config, :avatar, :avatar_id, :updated_at]

  defp legacy_profile(actor, %{data: %User{}, changes: changes}) do
    if legacy_role(actor) == :user and not Enum.all?(Map.keys(changes), &(&1 in @profile_fields)),
      do: {:error, :forbidden},
      else: :ok
  end

  defp legacy_profile(_actor, _changeset), do: :ok

  # `Brando.Trait.ProtectRole` checks a changeset built by the schema; this
  # checks one built any other way, against the role read afresh.
  defp legacy_role_change(actor, %{data: %User{} = user, changes: %{role: new_role}, valid?: true})
       when not is_nil(new_role) do
    if ProtectRole.allowed?(%{role: legacy_role(actor)}, user, new_role), do: :ok, else: {:error, :forbidden}
  end

  defp legacy_role_change(_actor, _changeset), do: :ok

  defp legacy_protect_superuser(actor, %{data: %User{id: id} = user, changes: changes}) when not is_nil(id) do
    if (Map.get(changes, :active) == false or not is_nil(Map.get(changes, :deleted_at))) and superuser_account?(user) and
         not ProtectPassword.allowed?(actor, user),
       do: {:error, :forbidden},
       else: :ok
  end

  defp legacy_protect_superuser(_actor, _changeset), do: :ok

  # Only checked, never saved: the caller writes its own changeset.
  defp with_stored_role(%{data: %User{id: id} = user} = changeset) when is_integer(id),
    do: %{changeset | data: %{user | role: stored_role(id) || user.role}}

  defp with_stored_role(changeset), do: changeset

  defp superuser_account?(%User{role: :superuser}), do: true
  defp superuser_account?(_), do: false

  defp legacy_role(%Scope{user_id: id}) when is_integer(id), do: stored_role(id)
  defp legacy_role(%{role: role}), do: role
  defp legacy_role(%{id: id}) when is_integer(id), do: stored_role(id)
  defp legacy_role(_), do: nil

  # An admin view holds the user it mounted with; the role may have changed since.
  defp fresh_role(%User{id: id} = user) when is_integer(id), do: %{user | role: stored_role(id) || user.role}
  defp fresh_role(actor), do: actor

  defp stored_role(id) do
    import Ecto.Query, only: [from: 2]
    Repo.one(from(u in User, where: u.id == ^id, select: u.role), prefix: "public")
  end

  defp user_id(%Scope{user_id: id}), do: id
  defp user_id(%{id: id}), do: id
  defp user_id(_), do: nil
end

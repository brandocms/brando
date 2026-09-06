defmodule Brando.Authorization.Groups do
  @moduledoc """
  Group and membership administration with scope, delegation and audit checks.

  Every write reloads authority inside a transaction. Group updates require the
  version shown to the administrator, so concurrent edits cannot silently erase
  permissions. The shared administration lock also protects the last Superuser.
  """
  import Ecto.Query, only: [from: 2]
  alias Brando.Authorization.{AuditEvent, Catalog, Engine, Grant, Group, Membership, Scope}
  alias Brando.Repo
  alias Ecto.Changeset

  @lock_id 303_20260906

  @doc "Lists groups and member counts in the authorized scope."
  def list(%Scope{} = scope) do
    with :ok <- Engine.authorize(scope, :read, :groups) do
      groups =
        scoped(scope)
        |> Ecto.Query.order_by([g], asc: g.name, asc: g.id)
        |> Repo.all()
        |> Repo.preload([:grants, :memberships])

      {:ok, groups}
    end
  end

  @doc "Gets an authorized group; IDs from other scopes remain inaccessible."
  def get(scope, id) do
    with :ok <- Engine.authorize(scope, :read, :groups),
         %Group{} = group <- find(scope, id) do
      {:ok, Repo.preload(group, [:grants, :memberships])}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  @doc "Creates an empty group or one with an explicitly reviewed permission set."
  def create(%Scope{} = scope, attrs, permissions \\ []) do
    transact(fn ->
      authorize!(scope, :create)
      permissions = validate_permissions!(scope, permissions)
      check_delegation!(scope, permissions)
      key = "group-" <> Ecto.UUID.generate()

      group = %Group{key: key, scope_kind: scope.kind, site_id: scope.site_id}

      case group |> Group.changeset(attrs) |> Repo.insert() do
        {:ok, group} ->
          replace_grants(group, permissions)
          audit(scope, "group.created", group, nil, %{name: group.name, permissions: permissions})
          Repo.preload(group, [:grants, :memberships])

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc "Saves a group and its grants atomically, rejecting stale form versions."
  def update(scope, id, attrs, permissions, expected_version) do
    transact(fn ->
      authorize!(scope, :update)
      group = find!(scope, id)
      check_editable!(group)
      if group.lock_version != expected_version, do: Repo.rollback(:stale)
      permissions = validate_permissions!(scope, permissions)
      before = permission_keys(group)
      # Existing grants outside a delegated manager's authority stay locked.
      # Only additions/removals need delegation; a description edit must not
      # fail because the group also contains an unchanged, locked permission.
      check_delegation!(scope, (before -- permissions) ++ (permissions -- before))

      changeset = group |> Group.changeset(attrs) |> Changeset.optimistic_lock(:lock_version)

      case Repo.update(changeset) do
        {:ok, saved} ->
          replace_grants(saved, permissions)

          audit(scope, "group.updated", saved, %{name: group.name, permissions: before}, %{
            name: saved.name,
            permissions: permissions
          })

          Repo.preload(saved, [:grants, :memberships])

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc "Deletes a custom group and its memberships, preserving audit history."
  def delete(scope, id, expected_version) do
    transact(fn ->
      authorize!(scope, :delete)
      group = find!(scope, id)
      if group.preset, do: Repo.rollback(:protected_group)
      if group.lock_version != expected_version, do: Repo.rollback(:stale)
      permissions = permission_keys(group)
      check_delegation!(scope, permissions)
      audit(scope, "group.deleted", group, %{name: group.name, permissions: permissions}, nil)
      Repo.delete!(group)
    end)
  end

  @doc "Assigns an existing account to a group within the administrator's scope."
  def add_member(scope, group_id, user_id) do
    transact(fn ->
      authorize!(scope, :assign)
      group = find!(scope, group_id)
      check_assignment!(scope, group)
      user = eligible_member!(user_id)
      check_directory_access!(scope, user.id)
      now = DateTime.utc_now()
      Repo.insert_all(Membership, [%{user_id: user.id, group_id: group.id, inserted_at: now}], on_conflict: :nothing)
      audit(scope, "membership.added", group, nil, %{user_id: user.id}, user.id)
      :ok
    end)
  end

  @doc "Revokes a group membership, including from already-open sessions."
  def remove_member(scope, group_id, user_id) do
    transact(fn ->
      authorize!(scope, :assign)
      group = find!(scope, group_id)
      check_assignment!(scope, group)
      protect_last_superuser!(group, user_id)
      Repo.delete_all(from(m in Membership, where: m.group_id == ^group.id and m.user_id == ^user_id))
      audit(scope, "membership.removed", group, %{user_id: user_id}, nil, user_id)
      :ok
    end)
  end

  @doc "Returns only directory fields safe for selecting a site group member."
  def directory(scope, search \\ "") do
    with :ok <- Engine.authorize(scope, :assign, :groups) do
      # A site administrator may select an account already assigned to that site.
      # Inviting previously unassigned identities is an installation operation.
      query =
        from(u in Brando.Users.User,
          where: u.active and is_nil(u.deleted_at),
          where: ilike(u.name, ^("%" <> search <> "%")),
          select: %{id: u.id, name: u.name},
          order_by: [asc: u.name],
          limit: 50
        )

      query =
        if scope.kind == :site and not Engine.superuser?(scope) do
          from(u in query,
            where:
              u.id in subquery(
                from(m in Membership,
                  join: g in Group,
                  on: g.id == m.group_id,
                  where: g.scope_kind == :site and g.site_id == ^scope.site_id,
                  select: m.user_id
                )
              )
          )
        else
          query
        end

      {:ok, Repo.all(query)}
    end
  end

  @doc "A pure save preview: which grants will be added and removed."
  def changes(group, permissions) do
    current = Enum.map(group.grants, & &1.permission_key)
    %{added: permissions -- current, removed: current -- permissions, members: length(group.memberships)}
  end

  @doc "Safe member summaries for an authorized group, including disabled accounts."
  def members(scope, group_id) do
    with {:ok, group} <- get(scope, group_id) do
      {:ok,
       Repo.all(
         from(u in Brando.Users.User,
           join: m in Membership,
           on: m.user_id == u.id,
           where: m.group_id == ^group.id,
           order_by: [asc: u.name],
           select: %{id: u.id, name: u.name, active: u.active}
         )
       )}
    end
  end

  @doc "Explains a member's effective grants in this scope only."
  def effective(scope, user_id) do
    with :ok <- Engine.authorize(scope, :read, :groups),
         true <-
           Repo.one(
             from(m in Membership,
               join: g in Group,
               on: m.group_id == g.id,
               where: m.user_id == ^user_id and g.id in subquery(from(g in scoped(scope), select: g.id)),
               select: count(m.user_id)
             )
           ) > 0 do
      snapshot = Engine.snapshot(%{scope | user_id: user_id})

      {:ok,
       Enum.map(Enum.filter(Catalog.all(), &(scope.kind in &1.scopes)), fn permission ->
         Map.put(permission, :explanation, Engine.explain(snapshot, permission.action, permission.subject))
       end)}
    else
      _ -> {:error, :forbidden}
    end
  end

  def history(scope, group_id) do
    with {:ok, group} <- get(scope, group_id) do
      events =
        Repo.all(
          from(e in AuditEvent,
            left_join: actor in Brando.Users.User,
            on: actor.id == e.actor_id,
            left_join: subject in Brando.Users.User,
            on: subject.id == e.subject_user_id,
            where: e.group_id == ^group.id,
            order_by: [desc: e.id],
            limit: 20,
            select: {e, actor.name, subject.name}
          )
        )

      {:ok,
       Enum.map(events, fn {event, actor_name, subject_name} ->
         Map.merge(event, %{actor_name: actor_name, subject_name: subject_name})
       end)}
    end
  end

  @doc false
  def lock! do
    Ecto.Adapters.SQL.query!(Repo.repo(), "SELECT pg_advisory_xact_lock($1)", [@lock_id])
  end

  @doc false
  def protect_account!(user_id) do
    group = Repo.one(from(g in Group, where: g.preset == :superuser and g.scope_kind == :installation))
    if group, do: protect_last_superuser!(group, user_id)
    :ok
  end

  defp transact(fun) do
    case Repo.transaction(fn ->
           lock!()
           fun.()
         end) do
      {:ok, _} = result ->
        Phoenix.PubSub.broadcast(Brando.pubsub(), "brando:authorization", {:authorization_changed, :all})
        result

      error ->
        error
    end
  end

  defp scoped(scope) do
    query = from(g in Group, where: g.scope_kind == ^scope.kind)

    if scope.site_id,
      do: from(g in query, where: g.site_id == ^scope.site_id),
      else: from(g in query, where: is_nil(g.site_id))
  end

  defp find(scope, id), do: Repo.one(from(g in scoped(scope), where: g.id == ^id))
  defp find!(scope, id), do: find(scope, id) || Repo.rollback(:not_found)

  defp authorize!(scope, action) do
    if Engine.authorize(scope, action, :groups) != :ok, do: Repo.rollback(:forbidden)
  end

  defp validate_permissions!(scope, permissions) when is_list(permissions) do
    catalog = Map.new(Catalog.all(), &{&1.key, &1})

    if Enum.all?(permissions, fn key ->
         case Map.get(catalog, key) do
           nil -> false
           permission -> scope.kind in permission.scopes
         end
       end), do: Enum.uniq(permissions), else: Repo.rollback(:invalid_permissions)
  end

  defp validate_permissions!(_, _), do: Repo.rollback(:invalid_permissions)

  defp check_delegation!(scope, permissions) do
    snapshot = Engine.snapshot(scope)

    unless snapshot.superuser? do
      catalog = Map.new(Catalog.all(), &{&1.key, &1})

      unless Enum.all?(permissions, fn key ->
               case Map.get(catalog, key) do
                 %{delegable: true} -> Map.has_key?(snapshot.grants, key)
                 _ -> false
               end
             end),
             do: Repo.rollback(:not_delegable)
    end
  end

  defp check_editable!(%{preset: :superuser}), do: Repo.rollback(:protected_group)
  defp check_editable!(_), do: :ok

  defp check_assignment!(scope, %{preset: :superuser}) do
    unless Engine.superuser?(scope), do: Repo.rollback(:forbidden)
  end

  defp check_assignment!(scope, group), do: check_delegation!(scope, permission_keys(group))

  defp eligible_member!(id) do
    case Repo.get(Brando.Users.User, id) do
      %{active: true, deleted_at: nil} = user -> user
      _ -> Repo.rollback(:inactive_account)
    end
  end

  defp check_directory_access!(%Scope{kind: :site} = scope, user_id) do
    unless Engine.superuser?(scope) do
      membership =
        Repo.one(
          from(m in Membership,
            join: g in Group,
            on: g.id == m.group_id,
            where: m.user_id == ^user_id and g.scope_kind == :site and g.site_id == ^scope.site_id,
            select: m.user_id,
            limit: 1
          )
        )

      if is_nil(membership), do: Repo.rollback(:forbidden)
    end
  end

  defp check_directory_access!(_, _), do: :ok

  defp protect_last_superuser!(%{preset: :superuser} = group, user_id) do
    member? = Repo.one(from(m in Membership, where: m.group_id == ^group.id and m.user_id == ^user_id, select: 1))

    others =
      Repo.one(
        from(m in Membership,
          join: u in Brando.Users.User,
          on: u.id == m.user_id,
          where: m.group_id == ^group.id and u.id != ^user_id and u.active and is_nil(u.deleted_at),
          select: count(m.user_id)
        )
      )

    if not is_nil(member?) and others == 0, do: Repo.rollback(:last_superuser)
  end

  defp protect_last_superuser!(_, _), do: :ok

  defp permission_keys(group) do
    Repo.all(from(p in Grant, where: p.group_id == ^group.id, select: p.permission_key))
  end

  defp replace_grants(group, keys) do
    Repo.delete_all(from(p in Grant, where: p.group_id == ^group.id))
    Repo.insert_all(Grant, Enum.map(keys, &%{group_id: group.id, permission_key: &1}))
  end

  defp audit(scope, action, group, before, after_value, user_id \\ nil) do
    Repo.insert!(%AuditEvent{
      actor_id: scope.user_id,
      action: action,
      group_id: group.id,
      subject_user_id: user_id,
      site_id: scope.site_id,
      before: before,
      after: after_value
    })
  end
end

defmodule Brando.Authorization.Engine do
  @moduledoc false
  import Ecto.Query, only: [from: 2, where: 3, put_query_prefix: 2]
  alias Brando.Authorization.{Catalog, Grant, Group, Membership, Scope, Snapshot}
  alias Brando.Repo

  def enabled?, do: Application.get_env(:brando, :authorization_mode, :legacy) == :groups

  @doc "Whether this account can enter any available administration scope."
  def backend_access?(actor) do
    can?(Scope.installation(actor), :access, :backend) or
      case Brando.Tenant.mode() do
        :none -> can?(Scope.standalone(actor), :access, :backend)
        _ -> Enum.any?(accessible_sites(actor))
      end
  end

  def accessible_sites(actor) do
    from(site in Brando.Sites.Site,
      where: site.status == :active,
      order_by: [asc: site.name, asc: site.id],
      preload: [:environments]
    )
    |> Repo.all()
    |> Enum.filter(&can?(Scope.site(actor, &1), :access, :backend))
  end

  def snapshot(%Scope{} = scope) do
    user = scope.user_id && Repo.get(Brando.Users.User, scope.user_id)

    with :ok <- eligible_user(user), :ok <- eligible_scope(scope) do
      groups =
        from(g in Group,
          join: m in Membership,
          on: m.group_id == g.id,
          left_join: p in Grant,
          on: p.group_id == g.id,
          where: m.user_id == ^scope.user_id,
          select: {g, p.permission_key}
        )
        |> Repo.all()

      superuser? = Enum.any?(groups, fn {g, _} -> g.preset == :superuser and g.scope_kind == :installation end)

      grants =
        groups
        |> Enum.filter(fn {group, key} -> not is_nil(key) and group_scope?(group, scope) end)
        |> Enum.reduce(%{}, fn {group, key}, acc ->
          Map.update(acc, key, [%{id: group.id, name: group.name}], &[%{id: group.id, name: group.name} | &1])
        end)

      %Snapshot{scope: scope, user: user, grants: grants, superuser?: superuser?}
    else
      {:error, reason} -> %Snapshot{scope: scope, user: user, reason: reason}
    end
  end

  def snapshot(actor), do: actor |> Scope.current() |> snapshot()

  def can?(%Snapshot{} = snapshot, action, subject), do: explain(snapshot, action, subject).allowed?
  def can?(actor, action, subject), do: actor |> snapshot() |> can?(action, subject)

  # Never accept a presentation snapshot as authority for a write.
  def authorize(%Snapshot{scope: scope}, action, subject), do: authorize(scope, action, subject)

  def authorize(actor, action, subject) do
    if can?(actor, action, subject), do: :ok, else: {:error, :forbidden}
  end

  def explain(%Snapshot{} = snapshot, action, subject) do
    permission =
      if own_profile?(snapshot, action, subject), do: Catalog.get(action, :profile), else: Catalog.get(action, subject)

    reason =
      cond do
        snapshot.reason -> snapshot.reason
        is_nil(permission) -> :unknown_permission
        snapshot.scope.kind not in permission.scopes -> :wrong_scope
        not subject_scope?(snapshot.scope, subject) -> :wrong_scope
        not has_backend_access?(snapshot) -> :backend_access_required
        not granted?(snapshot, permission.key) -> :missing_grant
        not protected_subject?(snapshot, action, subject) -> :protected_account
        not policy_allows?(snapshot.scope, action, subject) -> :policy_denied
        true -> nil
      end

    %{
      allowed?: is_nil(reason),
      reason: reason,
      permission: permission && permission.key,
      groups: if(permission, do: Map.get(snapshot.grants, permission.key, []), else: []),
      superuser?: snapshot.superuser?,
      scope: snapshot.scope
    }
  end

  def explain(actor, action, subject), do: actor |> snapshot() |> explain(action, subject)

  def scope(actor, action, schema) do
    scope_query(actor, action, Ecto.Queryable.to_query(schema), schema)
  end

  def scope_query(actor, action, query, schema) do
    snapshot = snapshot(actor)

    if schema == Brando.Users.User and action == :read and not can?(snapshot, action, schema) and
         can?(snapshot, :read, :profile) do
      query |> put_query_prefix("public") |> where([user], user.id == ^snapshot.scope.user_id)
    else
      do_scope_query(snapshot, action, query, schema)
    end
  end

  defp do_scope_query(snapshot, action, query, schema) do
    if can?(snapshot, action, schema) and query_scope?(snapshot.scope, schema) do
      query = put_query_prefix(query, query_prefix(snapshot.scope, schema))

      case policy(schema) do
        nil ->
          query

        module ->
          if function_exported?(module, :scope, 3),
            do: module.scope(snapshot.scope, action, query),
            else: where(query, [entry], false)
      end
    else
      where(query, [entry], false)
    end
  end

  def authorize_change(actor, action, %Ecto.Changeset{} = changeset) do
    snapshot = snapshot(actor)

    with true <- subject_scope?(snapshot.scope, changeset.data),
         {:ok, original} <- fresh_original(snapshot.scope, action, changeset.data),
         current_changeset <- %{changeset | data: original},
         proposed <- Ecto.Changeset.apply_changes(current_changeset),
         subject <- if(action == :create, do: proposed, else: original),
         true <- can?(snapshot, action, subject),
         true <- protected_changes?(snapshot, changeset),
         true <- policy_allows?(snapshot.scope, action, proposed),
         true <- publication_allowed?(snapshot, current_changeset) do
      :ok
    else
      _ -> {:error, :forbidden}
    end
  end

  defp fresh_original(_scope, :create, %{__meta__: %{state: :built}, id: nil} = entry), do: {:ok, entry}

  defp fresh_original(scope, action, %{__meta__: %{state: :loaded}, __struct__: schema, id: id})
       when action in [:update, :reorder, :restore] do
    # Lock the actual target while authorizing the resulting changes. A stale or
    # forged changeset's data cannot disguise a live entry as an unpublished one.
    query = from(entry in schema, where: entry.id == ^id, lock: "FOR UPDATE")

    case Repo.one(query, prefix: query_prefix(scope, schema)) do
      nil -> {:error, :not_found}
      entry -> {:ok, entry}
    end
  end

  defp fresh_original(_, _, _), do: {:error, :invalid_entry}

  def superuser?(actor) do
    case snapshot(actor) do
      %Snapshot{reason: nil, superuser?: true} -> true
      _ -> false
    end
  end

  defp eligible_user(%{active: true, deleted_at: nil}), do: :ok
  defp eligible_user(_), do: {:error, :inactive_account}

  defp eligible_scope(%Scope{kind: :standalone, site_id: nil, environment_id: nil, prefix: nil}) do
    if Brando.Tenant.mode() == :none, do: :ok, else: {:error, :wrong_scope}
  end

  defp eligible_scope(%Scope{kind: :installation, site_id: nil, environment_id: nil, prefix: nil}), do: :ok

  defp eligible_scope(%Scope{kind: :site, site_id: id} = scope) when is_integer(id) do
    case Repo.get(Brando.Sites.Site, id) do
      %{status: :active} = site ->
        if valid_site?(site) and valid_environment?(scope, site), do: :ok, else: {:error, :wrong_scope}

      _ ->
        {:error, :inactive_site}
    end
  end

  defp eligible_scope(_), do: {:error, :wrong_scope}

  defp valid_site?(site) do
    case Brando.Tenant.mode() do
      :multi -> true
      :single -> site.key == Brando.RuntimeConfig.get(:site_key)
      _ -> false
    end
  end

  defp valid_environment?(%Scope{environment_id: nil, prefix: nil}, _), do: true

  defp valid_environment?(%Scope{environment_id: id, prefix: prefix}, site) when is_integer(id) do
    case Repo.get(Brando.Environments.Environment, id) do
      %{site_id: site_id} = environment ->
        site_id == site.id and prefix == Brando.Tenant.prefix(site, environment)

      _ ->
        false
    end
  end

  defp valid_environment?(_, _), do: false

  defp group_scope?(group, scope), do: group.scope_kind == scope.kind and group.site_id == scope.site_id
  defp has_backend_access?(snapshot), do: granted?(snapshot, "brando.admin.access")
  defp granted?(%Snapshot{superuser?: true}, _), do: true
  defp granted?(%Snapshot{grants: grants}, key), do: Map.has_key?(grants, key)

  defp subject_scope?(scope, %{__meta__: %{state: :loaded, prefix: prefix}, __struct__: schema}) do
    if schema.__schema__(:prefix) == "public" do
      true
    else
      case scope do
        %Scope{kind: :standalone} -> prefix in [nil, "public"]
        %Scope{kind: :site, prefix: expected} when is_binary(expected) -> prefix == expected
        _ -> false
      end
    end
  end

  defp subject_scope?(_, _), do: true

  defp query_scope?(%Scope{kind: :site, prefix: nil}, schema), do: schema.__schema__(:prefix) == "public"
  defp query_scope?(_, _), do: true

  defp query_prefix(scope, schema),
    do: if(schema.__schema__(:prefix) == "public", do: "public", else: scope.prefix || "public")

  defp protected_subject?(%Snapshot{superuser?: true}, _, _), do: true

  defp protected_subject?(snapshot, action, %{__struct__: Brando.Users.User, id: id}) when action != :read do
    id == nil or id == snapshot.user.id or not superuser?(Scope.installation(%{id: id}))
  end

  defp protected_subject?(_, _, _), do: true

  defp protected_changes?(snapshot, %{data: %{__struct__: Brando.Users.User} = user, changes: changes}) do
    role_valid? = not Map.has_key?(changes, :role) or (is_nil(user.id) and changes.role == :user)
    credentials_valid? = snapshot.superuser? or user.id in [nil, snapshot.user.id] or not Map.has_key?(changes, :password)

    profile_valid? =
      can?(snapshot, :update, Brando.Users.User) or
        (user.id == snapshot.scope.user_id and
           Enum.all?(
             Map.keys(changes),
             &(&1 in [:name, :email, :password, :language, :config, :avatar, :avatar_id, :updated_at])
           ))

    role_valid? and credentials_valid? and profile_valid?
  end

  defp protected_changes?(_, _), do: true

  defp own_profile?(snapshot, action, %{__struct__: Brando.Users.User, id: id}) when action in [:read, :update] do
    id == snapshot.scope.user_id and not is_nil(id) and
      (snapshot.scope.kind == :site or not granted?(snapshot, "brando.users.#{action}"))
  end

  defp own_profile?(_, _, _), do: false

  defp publication_allowed?(snapshot, %{data: original, changes: changes} = changeset) do
    published? = Map.get(original, :status) == :published or Ecto.Changeset.get_field(changeset, :status) == :published
    scheduled? = Map.has_key?(changes, :publish_at)

    (not published? or map_size(changes) == 0 or can?(snapshot, :publish, original.__struct__)) and
      (not scheduled? or can?(snapshot, :schedule, original.__struct__))
  end

  defp policy_allows?(scope, action, subject) do
    schema = if is_struct(subject), do: subject.__struct__, else: subject

    case policy(schema) do
      nil -> true
      module -> function_exported?(module, :authorize, 3) and module.authorize(scope, action, subject) in [true, :ok]
    end
  end

  defp policy(schema) when is_atom(schema) do
    if function_exported?(schema, :__authorization__, 0) do
      module = Keyword.get(schema.__authorization__(), :policy)
      if module, do: Code.ensure_loaded?(module)
      module
    end
  end

  defp policy(_), do: nil
end

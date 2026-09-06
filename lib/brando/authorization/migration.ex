defmodule Brando.Authorization.Migration do
  @moduledoc """
  Explicit, idempotent migration from legacy roles to scoped group memberships.

  Run the report before enabling `config :brando, authorization_mode: :groups`.
  The migration creates grants only when a preset is first created. Re-running
  it never rewrites an administrator's permission edits.
  """
  import Ecto.Query, only: [from: 2]
  alias Brando.Authorization.{Catalog, Grant, Group, Groups, Membership, Scope}
  alias Brando.Repo

  @doc "Reports the intended mappings without changing the database."
  def report do
    users = Repo.all(Brando.Users.User)
    assignments = Repo.all(Brando.Users.UserSite)

    %{
      mode: Brando.Tenant.mode(),
      users: length(users),
      assignments: length(assignments),
      superusers: Enum.count(users, &(&1.role == :superuser)),
      unassigned_user_ids:
        if(Brando.Tenant.mode() == :multi,
          do:
            for(user <- users, user.role != :superuser, not Enum.any?(assignments, &(&1.user_id == user.id)), do: user.id),
          else: []
        ),
      application_rules: legacy_rules_report()
    }
  end

  @doc "Backfills scoped presets and memberships. Does not enable the new resolver."
  def run(opts \\ []) do
    if Keyword.get(opts, :dry_run, false) do
      {:ok, report()}
    else
      Repo.transaction(fn ->
        Groups.lock!()
        installation = Scope.installation(nil)
        superuser = ensure_preset(installation, :superuser)
        users = Repo.all(Brando.Users.User)

        Enum.each(users, fn user ->
          if user.role == :superuser,
            do: import_once("users", user.id, fn -> insert_membership(user.id, superuser.id) end)
        end)

        migrate_scopes(users)
        report()
      end)
    end
  end

  @doc "Seeds an explicitly selected scope. Intended for provisioning and operator setup."
  def seed_scope(%Scope{} = scope) do
    Repo.transaction(fn ->
      Groups.lock!()
      Enum.map([:user, :editor, :admin], &ensure_preset(scope, &1))
    end)
  end

  @doc "Explicit operator recovery: restores an eligible account's system membership."
  def recover_superuser(user) do
    result =
      Repo.transaction(fn ->
        Groups.lock!()
        current = Repo.get(Brando.Users.User, user.id)
        unless current && current.active && is_nil(current.deleted_at), do: Repo.rollback(:inactive_account)
        group = ensure_preset(Scope.installation(current), :superuser)
        insert_membership(current.id, group.id)

        Repo.insert!(%Brando.Authorization.AuditEvent{
          action: "operator.superuser_recovered",
          group_id: group.id,
          subject_user_id: current.id,
          after: %{user_id: current.id}
        })

        :ok
      end)

    if result == {:ok, :ok},
      do: Phoenix.PubSub.broadcast(Brando.pubsub(), "brando:authorization", {:authorization_changed, :all})

    result
  end

  defp migrate_scopes(users) do
    case Brando.Tenant.mode() do
      :none ->
        migrate_users(users, Scope.standalone(nil))

      :single ->
        site = Brando.Tenant.Registry.get_site_by_key(Brando.RuntimeConfig.get(:site_key))
        if is_nil(site), do: Repo.rollback(:site_not_found)
        migrate_users(users, Scope.site(nil, site))

      :multi ->
        Enum.each(Repo.all(Brando.Sites.Site), fn site ->
          scope = Scope.site(nil, site)
          presets = Map.new([:user, :editor, :admin], &{&1, ensure_preset(scope, &1)})

          Repo.all(from(a in Brando.Users.UserSite, where: a.site_id == ^site.id))
          |> Enum.each(fn assignment ->
            import_once("user_sites", assignment.id, fn ->
              insert_membership(assignment.user_id, presets[assignment.role].id)
            end)
          end)
        end)
    end
  end

  defp migrate_users(users, scope) do
    presets = Map.new([:user, :editor, :admin], &{&1, ensure_preset(scope, &1)})

    Enum.each(users, fn user ->
      source = "users:#{scope.kind}:#{scope.site_id}"
      if group = presets[user.role], do: import_once(source, user.id, fn -> insert_membership(user.id, group.id) end)
    end)
  end

  defp ensure_preset(scope, preset) do
    query = from(g in Group, where: g.scope_kind == ^scope.kind and g.preset == ^preset)

    query =
      if scope.site_id,
        do: from(g in query, where: g.site_id == ^scope.site_id),
        else: from(g in query, where: is_nil(g.site_id))

    case Repo.one(query) do
      nil ->
        group =
          Repo.insert!(%Group{
            key: Atom.to_string(preset),
            name: String.capitalize(Atom.to_string(preset)),
            description: description(preset),
            scope_kind: scope.kind,
            site_id: scope.site_id,
            preset: preset
          })

        grants = Enum.map(Catalog.preset_permissions(preset, scope.kind), &%{group_id: group.id, permission_key: &1})
        Repo.insert_all(Grant, grants)
        group

      group ->
        group
    end
  end

  defp insert_membership(user_id, group_id) do
    Repo.insert_all(Membership, [%{user_id: user_id, group_id: group_id, inserted_at: DateTime.utc_now()}],
      on_conflict: :nothing
    )
  end

  defp import_once(source, id, fun) do
    {count, _} =
      Repo.insert_all(
        "authorization_legacy_mappings",
        [%{source: source, source_id: id, inserted_at: DateTime.utc_now()}],
        on_conflict: :nothing,
        prefix: "public"
      )

    if count == 1, do: fun.()
  end

  defp description(:superuser), do: "Installation administration and access across active sites."
  defp description(:admin), do: "Manage content and settings within this workspace."
  defp description(:editor), do: "Create, edit and publish content."
  defp description(:user), do: "No workspace access until another group grants it."

  defp legacy_rules_report do
    module = Brando.authorization()

    if Code.ensure_loaded?(module) and function_exported?(module, :__rules__, 1) do
      "Review #{inspect(module)} before cutover: custom and conditional legacy rules require explicit policy mappings."
    end
  end
end

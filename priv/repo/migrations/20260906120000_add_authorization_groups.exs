defmodule Brando.Repo.Migrations.AddAuthorizationGroups do
  use Ecto.Migration

  def change do
    create table(:authorization_groups, prefix: "public") do
      add :key, :text, null: false
      add :name, :text, null: false
      add :description, :text
      add :scope_kind, :text, null: false
      add :site_id, references(:sites, prefix: "public", on_delete: :delete_all)
      add :preset, :text
      add :lock_version, :integer, null: false, default: 1
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:authorization_groups, [:scope_kind, "COALESCE(site_id, 0)", :key],
             prefix: "public",
             name: :authorization_groups_scoped_key_index
           )

    create unique_index(:authorization_groups, [:scope_kind, "COALESCE(site_id, 0)", :preset],
             prefix: "public",
             where: "preset IS NOT NULL",
             name: :authorization_groups_scoped_preset_index
           )

    create constraint(:authorization_groups, :authorization_groups_scope,
             prefix: "public",
             check:
               "(scope_kind = 'site' AND site_id IS NOT NULL) OR (scope_kind IN ('standalone', 'installation') AND site_id IS NULL)"
           )

    create constraint(:authorization_groups, :authorization_groups_preset,
             prefix: "public",
             check: "preset IS NULL OR preset IN ('user', 'editor', 'admin', 'superuser')"
           )

    create constraint(:authorization_groups, :authorization_groups_superuser_scope,
             prefix: "public",
             check: "preset IS DISTINCT FROM 'superuser' OR scope_kind = 'installation'"
           )

    create table(:authorization_group_permissions, prefix: "public", primary_key: false) do
      add :group_id, references(:authorization_groups, prefix: "public", on_delete: :delete_all), primary_key: true
      add :permission_key, :text, primary_key: true
    end

    create table(:authorization_user_groups, prefix: "public", primary_key: false) do
      add :user_id, references(:users, prefix: "public", on_delete: :delete_all), primary_key: true
      add :group_id, references(:authorization_groups, prefix: "public", on_delete: :delete_all), primary_key: true
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:authorization_user_groups, [:group_id], prefix: "public")

    # Remember imports separately from live memberships: retrying a migration
    # must never re-grant a membership that an administrator has revoked.
    create table(:authorization_legacy_mappings, prefix: "public", primary_key: false) do
      add :source, :text, primary_key: true
      add :source_id, :bigint, primary_key: true
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Deliberately retain historical actor/target IDs after account or group deletion.
    # These are audit identities, not associations to transfer to another user.
    create table(:authorization_audit_events, prefix: "public") do
      add :actor_id, :bigint
      add :action, :text, null: false
      add :group_id, :bigint
      add :subject_user_id, :bigint
      add :site_id, :bigint
      add :before, :map
      add :after, :map
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:authorization_audit_events, [:group_id, :inserted_at], prefix: "public")
  end
end

defmodule Brando.Repo.Migrations.Brando213AddMCPConnections do
  use Ecto.Migration

  @moduledoc """
  The remote MCP endpoint (`Brando.MCP`), off until an administrator turns it
  on for a site environment:

    * `mcp_settings` — the switch, one row per site environment (or one row
      without tenancy).
    * `mcp_grants` — the connections people approve: a user, the client
      (its Client ID Metadata Document URL and name), the site environment
      and resource it is bound to, and when it was revoked.
    * `mcp_tokens` — access and refresh tokens, stored as SHA-256 hashes only.
    * `mcp_authorization_codes` — one-time codes, also hashed, that last a
      minute.

  Users, sites and environments live in `public`, and so do these tables.
  """

  def up do
    create_if_not_exists table(:mcp_settings, prefix: "public") do
      add :site_id, references(:sites, on_delete: :delete_all, prefix: "public")
      add :environment_id, references(:environments, on_delete: :delete_all, prefix: "public")
      add :enabled, :boolean, null: false, default: false
      add :changed_by_id, references(:users, on_delete: :nilify_all, prefix: "public")
      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists unique_index(
                           :mcp_settings,
                           ["coalesce(site_id, 0)", "coalesce(environment_id, 0)"],
                           name: :mcp_settings_scope_index,
                           prefix: "public"
                         )

    create_if_not_exists table(:mcp_grants, prefix: "public") do
      add :user_id, references(:users, on_delete: :delete_all, prefix: "public"), null: false
      add :site_id, references(:sites, on_delete: :delete_all, prefix: "public")
      add :environment_id, references(:environments, on_delete: :delete_all, prefix: "public")
      add :resource, :text, null: false
      add :client_id, :text, null: false
      add :client_name, :text, null: false
      add :redirect_uri, :text, null: false
      add :scope, :text, null: false
      add :last_used_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec
      add :revoked_by_id, references(:users, on_delete: :nilify_all, prefix: "public")
      add :revoked_reason, :string
      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists index(:mcp_grants, [:user_id], prefix: "public")
    create_if_not_exists index(:mcp_grants, [:site_id, :environment_id], prefix: "public")

    create_if_not_exists table(:mcp_tokens, prefix: "public") do
      add :grant_id, references(:mcp_grants, on_delete: :delete_all, prefix: "public"), null: false
      add :kind, :string, null: false
      add :token_hash, :binary, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :rotated_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec
      add :last_used_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create_if_not_exists unique_index(:mcp_tokens, [:token_hash], prefix: "public")
    create_if_not_exists index(:mcp_tokens, [:grant_id], prefix: "public")

    create_if_not_exists table(:mcp_authorization_codes, prefix: "public") do
      add :code_hash, :binary, null: false
      add :user_id, references(:users, on_delete: :delete_all, prefix: "public"), null: false
      add :site_id, references(:sites, on_delete: :delete_all, prefix: "public")
      add :environment_id, references(:environments, on_delete: :delete_all, prefix: "public")
      add :resource, :text, null: false
      add :client_id, :text, null: false
      add :client_name, :text, null: false
      add :redirect_uri, :text, null: false
      add :code_challenge, :string, null: false
      add :scope, :text, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :used_at, :utc_datetime_usec
      add :grant_id, references(:mcp_grants, on_delete: :nilify_all, prefix: "public")
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create_if_not_exists unique_index(:mcp_authorization_codes, [:code_hash], prefix: "public")
    create_if_not_exists index(:mcp_authorization_codes, [:expires_at], prefix: "public")
  end

  def down do
    drop_if_exists table(:mcp_authorization_codes, prefix: "public")
    drop_if_exists table(:mcp_tokens, prefix: "public")
    drop_if_exists table(:mcp_grants, prefix: "public")
    drop_if_exists table(:mcp_settings, prefix: "public")
  end
end

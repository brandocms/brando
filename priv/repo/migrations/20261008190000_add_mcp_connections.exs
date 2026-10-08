defmodule BrandoIntegration.Repo.Migrations.AddMCPConnections do
  use Ecto.Migration

  # Mirrors the brando_213 upgrade migration for the test schema.
  @moduledoc """
  The remote MCP endpoint (`Brando.MCP`): the switch per site environment,
  the connections people approve, their tokens and the authorization codes
  that start them.
  """

  def change do
    create table(:mcp_settings) do
      add :site_id, references(:sites, on_delete: :delete_all)
      add :environment_id, references(:environments, on_delete: :delete_all)
      add :enabled, :boolean, null: false, default: false
      add :changed_by_id, references(:users, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:mcp_settings, ["coalesce(site_id, 0)", "coalesce(environment_id, 0)"],
             name: :mcp_settings_scope_index
           )

    create table(:mcp_grants) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :site_id, references(:sites, on_delete: :delete_all)
      add :environment_id, references(:environments, on_delete: :delete_all)
      add :resource, :text, null: false
      add :client_id, :text, null: false
      add :client_name, :text, null: false
      add :redirect_uri, :text, null: false
      add :scope, :text, null: false
      add :last_used_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec
      add :revoked_by_id, references(:users, on_delete: :nilify_all)
      add :revoked_reason, :string
      timestamps(type: :utc_datetime_usec)
    end

    create index(:mcp_grants, [:user_id])
    create index(:mcp_grants, [:site_id, :environment_id])

    create table(:mcp_tokens) do
      add :grant_id, references(:mcp_grants, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :token_hash, :binary, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :rotated_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec
      add :last_used_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:mcp_tokens, [:token_hash])
    create index(:mcp_tokens, [:grant_id])

    create table(:mcp_authorization_codes) do
      add :code_hash, :binary, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :site_id, references(:sites, on_delete: :delete_all)
      add :environment_id, references(:environments, on_delete: :delete_all)
      add :resource, :text, null: false
      add :client_id, :text, null: false
      add :client_name, :text, null: false
      add :redirect_uri, :text, null: false
      add :code_challenge, :string, null: false
      add :scope, :text, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :used_at, :utc_datetime_usec
      add :grant_id, references(:mcp_grants, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:mcp_authorization_codes, [:code_hash])
    create index(:mcp_authorization_codes, [:expires_at])
  end
end

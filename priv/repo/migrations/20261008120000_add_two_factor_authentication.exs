defmodule BrandoIntegration.Repo.Migrations.AddTwoFactorAuthentication do
  use Ecto.Migration

  # Mirrors the brando_204 upgrade migration for the test schema.
  @moduledoc """
  Two-factor authentication, sign-in lockout, recovery codes, the security
  event log and the installation's two-factor policy.
  """

  def change do
    create table(:users_security) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :totp_secret, :text
      add :totp_enabled_at, :utc_datetime
      add :totp_last_step, :bigint
      add :failed_attempts, :integer, null: false, default: 0
      add :failures_since, :utc_datetime
      add :locked_until, :utc_datetime
      timestamps()
    end

    create unique_index(:users_security, [:user_id])

    create table(:users_recovery_codes) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :hashed_code, :binary, null: false
      add :used_at, :utc_datetime
      timestamps(updated_at: false)
    end

    create unique_index(:users_recovery_codes, [:user_id, :hashed_code])

    create table(:users_security_events) do
      add :user_id, references(:users, on_delete: :nilify_all)
      add :actor_id, references(:users, on_delete: :nilify_all)
      add :action, :string, null: false
      add :ip, :string
      add :user_agent, :string
      add :details, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:users_security_events, [:user_id, :inserted_at])
    create index(:users_security_events, [:inserted_at])

    create table(:users_security_policy) do
      add :two_factor, :string, null: false, default: "off"
      add :two_factor_roles, {:array, :string}, null: false, default: []
      add :two_factor_group_ids, {:array, :bigint}, null: false, default: []
      add :updated_by_id, references(:users, on_delete: :nilify_all)
      timestamps()
    end
  end
end

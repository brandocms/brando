defmodule Brando.Repo.Migrations.Brando204AddTwoFactorAuthentication do
  use Ecto.Migration

  @moduledoc """
  Two-factor authentication for admin users.

    * `users_security` — one row per user who has set up two-factor
      authentication or failed to sign in: the encrypted TOTP secret, when it
      was turned on, the last time step a code was used for (so a code works
      once), and the failed attempts and lockout. These are not columns on
      `users`, since the user form casts every column of the User blueprint.
    * `users_recovery_codes` — keyed hashes of the one-time recovery codes.
    * `users_security_events` — sign-ins, failed sign-ins, lockouts and
      changes to passwords and two-factor settings.
    * `users_security_policy` — the installation's one row saying who must
      use two-factor authentication.

  Users live in the `public` schema only, and so do these tables.
  """

  def up do
    create_if_not_exists table(:users_security, prefix: "public") do
      add :user_id, references(:users, on_delete: :delete_all, prefix: "public"), null: false
      add :totp_secret, :text
      add :totp_enabled_at, :utc_datetime
      add :totp_last_step, :bigint
      add :failed_attempts, :integer, null: false, default: 0
      add :locked_until, :utc_datetime
      timestamps()
    end

    create_if_not_exists unique_index(:users_security, [:user_id], prefix: "public")

    create_if_not_exists table(:users_recovery_codes, prefix: "public") do
      add :user_id, references(:users, on_delete: :delete_all, prefix: "public"), null: false
      add :hashed_code, :binary, null: false
      add :used_at, :utc_datetime
      timestamps(updated_at: false)
    end

    create_if_not_exists unique_index(:users_recovery_codes, [:user_id, :hashed_code], prefix: "public")

    create_if_not_exists table(:users_security_events, prefix: "public") do
      add :user_id, references(:users, on_delete: :nilify_all, prefix: "public")
      add :actor_id, references(:users, on_delete: :nilify_all, prefix: "public")
      add :action, :string, null: false
      add :ip, :string
      add :user_agent, :string
      add :details, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create_if_not_exists index(:users_security_events, [:user_id, :inserted_at], prefix: "public")
    create_if_not_exists index(:users_security_events, [:inserted_at], prefix: "public")

    create_if_not_exists table(:users_security_policy, prefix: "public") do
      add :two_factor, :string, null: false, default: "off"
      add :two_factor_roles, {:array, :string}, null: false, default: []
      add :two_factor_group_ids, {:array, :bigint}, null: false, default: []
      add :updated_by_id, references(:users, on_delete: :nilify_all, prefix: "public")
      timestamps()
    end
  end

  def down do
    drop_if_exists table(:users_security_policy, prefix: "public")
    drop_if_exists table(:users_security_events, prefix: "public")
    drop_if_exists table(:users_recovery_codes, prefix: "public")
    drop_if_exists table(:users_security, prefix: "public")
  end
end

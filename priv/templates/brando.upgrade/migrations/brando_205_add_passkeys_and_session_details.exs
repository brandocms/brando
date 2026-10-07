defmodule Brando.Repo.Migrations.Brando205AddPasskeysAndSessionDetails do
  use Ecto.Migration

  @moduledoc """
  Passkeys, a session list and re-authentication for admin users.

    * `users_passkeys` — a user's passkeys (WebAuthn credentials): the name
      they gave the device, the credential id, its public key and signature
      counter, and when it was last used.
    * `users_tokens` gains `ip`, `user_agent` and `last_used_at`, for the list
      of a user's sessions, and `confirmed_at`, when the session last gave a
      password, a code or a passkey, for actions that ask again after a few
      minutes. Sessions from before this migration have none of these, and are
      asked to confirm before such an action.

  Users live in the `public` schema only, and so do these tables.
  """

  def up do
    create_if_not_exists table(:users_passkeys, prefix: "public") do
      add :user_id, references(:users, on_delete: :delete_all, prefix: "public"), null: false
      add :name, :string, null: false
      add :credential_id, :binary, null: false
      add :cose_key, :binary, null: false
      add :sign_count, :bigint, null: false, default: 0
      add :aaguid, :binary
      add :last_used_at, :utc_datetime
      timestamps()
    end

    create_if_not_exists unique_index(:users_passkeys, [:credential_id], prefix: "public")
    create_if_not_exists index(:users_passkeys, [:user_id], prefix: "public")

    alter table(:users_tokens, prefix: "public") do
      add_if_not_exists :ip, :string
      add_if_not_exists :user_agent, :string
      add_if_not_exists :last_used_at, :naive_datetime
      add_if_not_exists :confirmed_at, :naive_datetime
    end
  end

  def down do
    alter table(:users_tokens, prefix: "public") do
      remove_if_exists :ip, :string
      remove_if_exists :user_agent, :string
      remove_if_exists :last_used_at, :naive_datetime
      remove_if_exists :confirmed_at, :naive_datetime
    end

    drop_if_exists table(:users_passkeys, prefix: "public")
  end
end

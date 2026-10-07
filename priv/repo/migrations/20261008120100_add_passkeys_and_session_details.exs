defmodule BrandoIntegration.Repo.Migrations.AddPasskeysAndSessionDetails do
  use Ecto.Migration

  # Mirrors the brando_205 upgrade migration for the test schema.
  @moduledoc """
  Passkeys, and what the sessions list and re-authentication need to know
  about a session.
  """

  def change do
    create table(:users_passkeys) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :credential_id, :binary, null: false
      add :cose_key, :binary, null: false
      add :sign_count, :bigint, null: false, default: 0
      add :aaguid, :binary
      add :last_used_at, :utc_datetime
      timestamps()
    end

    create unique_index(:users_passkeys, [:credential_id])
    create index(:users_passkeys, [:user_id])

    alter table(:users_tokens) do
      add :ip, :string
      add :user_agent, :string
      add :last_used_at, :naive_datetime
      add :confirmed_at, :naive_datetime
    end
  end
end

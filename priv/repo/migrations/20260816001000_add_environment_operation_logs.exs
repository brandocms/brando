defmodule Brando.Repo.Migrations.AddEnvironmentOperationLogs do
  use Ecto.Migration

  @moduledoc """
  Test/e2e mirror of `priv/templates/brando.upgrade/migrations/brando_159_*`.
  """

  def change do
    create table(:environment_operation_logs, prefix: "public") do
      add :site_id, references(:sites, prefix: "public", on_delete: :delete_all), null: false

      add :source_environment_id,
          references(:environments, prefix: "public", on_delete: :nilify_all)

      add :target_environment_id,
          references(:environments, prefix: "public", on_delete: :nilify_all)

      add :creator_id, references(:users, prefix: "public", on_delete: :nilify_all)
      add :operation, :text, null: false
      add :archive_schema, :text
      add :note, :text
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:environment_operation_logs, [:site_id, :inserted_at], prefix: "public")

    create constraint(:environment_operation_logs, :environment_operation_logs_valid_operation,
             prefix: "public",
             check: "operation IN ('copy', 'set_live', 'rollback', 'create', 'delete')"
           )
  end
end

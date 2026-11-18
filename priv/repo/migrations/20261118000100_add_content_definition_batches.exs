defmodule BrandoIntegration.Repo.Migrations.AddContentDefinitionBatches do
  use Ecto.Migration

  # Mirrors the brando_232 upgrade migration for the test schema.
  @moduledoc """
  `content_definition_batches`: each apply of a release's module definitions,
  and each revert of one (`Brando.Content.DefinitionBatch`).
  """

  def change do
    create table(:content_definition_batches) do
      add :batch_id, :uuid, null: false
      add :source, :text, null: false
      add :release, :text
      add :run_id, :text
      add :definitions, :map, null: false, default: %{}
      add :reverts_batch_id, :uuid
      add :applied_by_id, references(:users, on_delete: :nilify_all)
      add :applied_at, :utc_datetime_usec, null: false
      add :confirmed_at, :utc_datetime_usec
      add :confirmed_by_id, references(:users, on_delete: :nilify_all)
      add :confirmed_how, :text
      add :reverted_at, :utc_datetime_usec
      add :reverted_by_id, references(:users, on_delete: :nilify_all)
      add :revert_batch_id, :uuid
    end

    create unique_index(:content_definition_batches, [:batch_id])
  end
end

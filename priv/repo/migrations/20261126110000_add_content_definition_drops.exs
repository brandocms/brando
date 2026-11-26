defmodule BrandoIntegration.Repo.Migrations.AddContentDefinitionDrops do
  use Ecto.Migration

  # Mirrors the brando_253 upgrade migration for the test schema.
  @moduledoc """
  `content_definition_drops`: the ref and var rows a release apply dropped
  from blocks, kept for a revert (`Brando.Content.DefinitionDrop`).
  """

  def change do
    create table(:content_definition_drops) do
      add :batch_id, :uuid, null: false
      add :module_uid, :text, null: false
      add :block_id, :integer, null: false
      add :kind, :text, null: false
      add :key, :text, null: false
      add :row, :map, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:content_definition_drops, [:batch_id, :module_uid])
  end
end

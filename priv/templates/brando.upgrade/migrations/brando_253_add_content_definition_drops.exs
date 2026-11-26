defmodule Brando.Repo.Migrations.Brando253AddContentDefinitionDrops do
  use Ecto.Migration

  @moduledoc """
  In every site environment, `content_definition_drops`: the ref and var rows
  a release apply dropped from blocks, because the release removed their
  key and the operator chose to drop what blocks held in it
  (`Brando.Content.DefinitionDrop`). Each row is stored whole, as the
  database had it, under the apply's `batch_id`, so a revert of that apply
  can put it back. Keeping the apply, or the next release apply, deletes them.
  """

  def up do
    for prefix <- prefixes() do
      create_if_not_exists table(:content_definition_drops, prefix: prefix) do
        add :batch_id, :uuid, null: false
        add :module_uid, :text, null: false
        add :block_id, :integer, null: false
        add :kind, :text, null: false
        add :key, :text, null: false
        add :row, :map, null: false
        add :inserted_at, :utc_datetime_usec, null: false
      end

      create_if_not_exists index(:content_definition_drops, [:batch_id, :module_uid], prefix: prefix)
    end
  end

  def down do
    for prefix <- prefixes() do
      drop_if_exists table(:content_definition_drops, prefix: prefix)
    end
  end

  # Every site environment, or only the one named by the migrator's prefix:
  # `Brando.Environments.ArchiveUpgrade` runs this again in an archive
  # restored from before it ran.
  defp prefixes do
    case prefix() do
      "tenant_" <> _ = environment ->
        [environment]

      _ ->
        %{rows: rows} =
          repo().query!(
            "SELECT nspname FROM pg_namespace WHERE nspname = 'public' OR nspname ~ '^tenant_[a-z0-9-]+_[a-z0-9-]+$'"
          )

        Enum.map(rows, &hd/1)
    end
  end
end

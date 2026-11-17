defmodule Brando.Repo.Migrations.Brando231AddContentDefinitionApplies do
  use Ecto.Migration

  @moduledoc """
  In every site environment, `content_definition_applies`: one row each time a
  module or table template definition was applied from files (a release's
  `priv/modules`, `mix brando.modules import`, the admin's ZIP import or the
  dev watcher), or found equal to them and recorded as applied
  (`Brando.Content.DefinitionApply`).

  The latest row for a definition is the environment's own baseline: planning
  a release's definitions compares the database with what was last applied
  here, not with the developer's lockfile. Definitions belong to an
  environment's content, so the table lives in each environment. Users live
  in `public`, so `applied_by_id` names that schema.
  """

  def up do
    for prefix <- prefixes() do
      create_if_not_exists table(:content_definition_applies, prefix: prefix) do
        add :kind, :text, null: false
        add :uid, :text, null: false
        add :digest, :text, null: false
        add :previous_digest, :text
        add :previous, :map
        add :action, :text, null: false
        add :source, :text, null: false
        add :release, :text
        add :references, :map, null: false, default: %{}
        add :batch_id, :uuid, null: false
        add :applied_by_id, references(:users, prefix: "public", on_delete: :nilify_all)
        add :applied_at, :utc_datetime_usec, null: false
      end

      create_if_not_exists index(:content_definition_applies, [:kind, :uid, :id], prefix: prefix)
      create_if_not_exists index(:content_definition_applies, [:batch_id], prefix: prefix)
    end
  end

  def down do
    for prefix <- prefixes() do
      drop_if_exists table(:content_definition_applies, prefix: prefix)
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

defmodule Brando.Repo.Migrations.Brando232AddContentDefinitionBatches do
  use Ecto.Migration

  @moduledoc """
  In every site environment, `content_definition_batches`: one row per apply
  of a release's module definitions from the admin or `rpc`, and per revert
  of one (`Brando.Content.DefinitionBatch`). Its `content_definition_applies`
  rows share its `batch_id`.

  An apply stays revertible until a superuser keeps it, or the next release
  apply confirms it: `confirmed_at` says when, `reverted_at` when it was
  reverted instead. `run_id` follows the entry renders the apply queued.
  Users live in `public`, so the user columns name that schema.
  """

  def up do
    for prefix <- prefixes() do
      create_if_not_exists table(:content_definition_batches, prefix: prefix) do
        add :batch_id, :uuid, null: false
        add :source, :text, null: false
        add :release, :text
        add :run_id, :text
        add :definitions, :map, null: false, default: %{}
        add :reverts_batch_id, :uuid
        add :applied_by_id, references(:users, prefix: "public", on_delete: :nilify_all)
        add :applied_at, :utc_datetime_usec, null: false
        add :confirmed_at, :utc_datetime_usec
        add :confirmed_by_id, references(:users, prefix: "public", on_delete: :nilify_all)
        add :confirmed_how, :text
        add :reverted_at, :utc_datetime_usec
        add :reverted_by_id, references(:users, prefix: "public", on_delete: :nilify_all)
        add :revert_batch_id, :uuid
      end

      create_if_not_exists unique_index(:content_definition_batches, [:batch_id], prefix: prefix)
    end
  end

  def down do
    for prefix <- prefixes() do
      drop_if_exists table(:content_definition_batches, prefix: prefix)
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

defmodule Brando.Migrations.Brando203AddEntryNotesTest do
  # Runs the upgrade template inside the sandbox transaction against tables
  # rolled back to before it; Postgres DDL is transactional, so everything is
  # undone afterwards.
  use ExUnit.Case
  use Brando.ConnCase

  alias BrandoIntegration.Repo

  @template Application.app_dir(:brando, "priv/templates/brando.upgrade/migrations/brando_203_add_entry_notes.exs")
  @tenant "tenant_acme_production"

  defp rows(sql, params), do: Repo.query!(sql, params).rows

  defp columns(schema, table) do
    "SELECT column_name FROM information_schema.columns WHERE table_schema = $1 AND table_name = $2"
    |> rows([schema, table])
    |> List.flatten()
  end

  # Where each foreign key of `table` in `schema` points: `[{column, schema, table}]`
  defp references(schema, table) do
    """
    SELECT kcu.column_name, ccu.table_schema, ccu.table_name
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
      ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
    JOIN information_schema.constraint_column_usage ccu
      ON tc.constraint_name = ccu.constraint_name AND tc.table_schema = ccu.constraint_schema
    WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_schema = $1 AND tc.table_name = $2
    """
    |> rows([schema, table])
    |> Enum.map(&List.to_tuple/1)
    |> Enum.sort()
  end

  defp run_template do
    [{module, _bytecode}] = Code.compile_file(@template)

    try do
      Ecto.Migrator.up(Repo, System.unique_integer([:positive]), module, log: false, migration_lock: false)
    after
      :code.purge(module)
      :code.delete(module)
    end
  end

  test "creates the notes tables in public and every tenant schema, users referenced in public" do
    Repo.query!("DROP TABLE note_mentions")
    Repo.query!("DROP TABLE entry_notes")
    Repo.query!(~s(CREATE SCHEMA "#{@tenant}"))

    run_template()

    for schema <- ["public", @tenant] do
      assert ~w(entry_type entry_id parent_id block_uid field_path range anchor_label body author_id resolved_at
                resolved_by_id detached_at text_removed_at deleted_at) -- columns(schema, "entry_notes") == []

      assert ~w(note_id user_id emailed_at inserted_at) -- columns(schema, "note_mentions") == []

      assert references(schema, "entry_notes") == [
               {"author_id", "public", "users"},
               {"parent_id", schema, "entry_notes"},
               {"resolved_by_id", "public", "users"}
             ]

      assert references(schema, "note_mentions") == [
               {"note_id", schema, "entry_notes"},
               {"user_id", "public", "users"}
             ]
    end
  end
end

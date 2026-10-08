defmodule Brando.Migrations.Brando203AddEntryNotesTest do
  # Runs the upgrade template inside the sandbox transaction against tables
  # rolled back to before it; Postgres DDL is transactional, so everything is
  # undone afterwards.
  use ExUnit.Case
  use Brando.ConnCase

  import Brando.MigrationTemplates

  @template "brando_203_add_entry_notes.exs"
  @tenant "tenant_acme_staging"
  @tables ~w(entry_notes note_mentions)

  test "creates the notes tables in public and every environment, users referenced in public, and drops them" do
    expected = Map.new(@tables, &{&1, {column_definitions("public", &1), indexes("public", &1)}})
    query!("DROP TABLE note_mentions")
    query!("DROP TABLE entry_notes")
    create_environment(@tenant)

    version = up(@template)

    for schema <- ["public", @tenant] do
      for table <- @tables do
        assert {column_definitions(schema, table), indexes(schema, table)} == expected[table]
      end

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

    down(@template, version)

    for schema <- ["public", @tenant], table <- @tables do
      refute table?(schema, table)
    end
  end
end

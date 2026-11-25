defmodule Brando.Migrations.Brando250AddSSGContentChangesTest do
  use Brando.ConnCase

  import Brando.MigrationTemplates,
    only: [
      column_definitions: 2,
      columns: 2,
      column_set: 2,
      down: 2,
      indexes: 2,
      query!: 1,
      references: 2,
      table?: 2,
      up: 1
    ]

  @file_name "brando_250_add_ssg_content_changes.exs"

  test "creates the table of content changes and the build's start, in public, and rolls back" do
    expected = column_definitions("public", "ssg_content_changes")
    expected_started_at = column_set("public", %{"ssg_builds" => ["started_at"]})
    expected_indexes = indexes("public", "ssg_content_changes")
    expected_references = references("public", "ssg_content_changes")
    query!("DROP TABLE public.ssg_content_changes")
    query!("ALTER TABLE public.ssg_builds DROP COLUMN started_at")

    version = up(@file_name)

    assert column_definitions("public", "ssg_content_changes") == expected
    assert indexes("public", "ssg_content_changes") == expected_indexes
    assert references("public", "ssg_content_changes") == expected_references
    assert column_set("public", %{"ssg_builds" => ["started_at"]}) == expected_started_at
    assert "started_at" in Enum.map(Brando.SSG.Build.__schema__(:fields), &to_string/1)
    assert Brando.Tenant.SharedTables.member?("ssg_content_changes")

    down(@file_name, version)

    refute table?("public", "ssg_content_changes")
    refute "started_at" in columns("public", "ssg_builds")
  end
end

defmodule Brando.Migrations.Brando246AddMediaDropToModulesTest do
  # Runs the upgrade template inside the sandbox transaction against tables
  # rolled back to before it; Postgres DDL is transactional, so everything
  # is undone afterwards.
  use ExUnit.Case
  use Brando.ConnCase

  import Brando.MigrationTemplates

  @template "brando_246_add_media_drop_to_modules.exs"
  @tenant "tenant_acme_staging"
  @columns ~w(media_drop_child media_drop_ref)

  defp media_drop(schema),
    do: schema |> column_definitions("content_modules") |> Enum.filter(&(elem(&1, 0) in @columns))

  test "adds media_drop_child and media_drop_ref to modules in public and every environment, empty, and removes them" do
    expected = media_drop("public")
    assert length(expected) == 2
    query!("ALTER TABLE content_modules DROP COLUMN media_drop_child, DROP COLUMN media_drop_ref")
    create_environment(@tenant, ["content_modules"])

    modules =
      Map.new(["public", @tenant], fn schema ->
        [[id]] =
          rows("""
          INSERT INTO "#{schema}".content_modules
            (uid, name, namespace, help_text, class, code, type, sequence, inserted_at, updated_at)
          VALUES ('m246', '{"en": "Row"}', '{"en": "general"}', '{"en": ""}', 'row', '', 'liquid', 0, NOW(), NOW())
          RETURNING id
          """)

        {schema, id}
      end)

    version = up(@template)

    for schema <- ["public", @tenant] do
      assert media_drop(schema) == expected
    end

    for {schema, id} <- modules do
      assert rows(~s(SELECT class, media_drop_child, media_drop_ref FROM "#{schema}".content_modules WHERE id = $1), [id]) ==
               [["row", nil, nil]]
    end

    down(@template, version)

    for schema <- ["public", @tenant], do: assert(media_drop(schema) == [])
  end
end

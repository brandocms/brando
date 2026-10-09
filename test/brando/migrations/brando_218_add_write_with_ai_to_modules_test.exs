defmodule Brando.Migrations.Brando218AddWriteWithAIToModulesTest do
  # Runs the upgrade template inside the sandbox transaction against tables
  # rolled back to before it; Postgres DDL is transactional, so everything
  # is undone afterwards.
  use ExUnit.Case
  use Brando.ConnCase

  import Brando.MigrationTemplates

  @template "brando_218_add_write_with_ai_to_modules.exs"
  @tenant "tenant_acme_staging"

  defp write_with_ai(schema),
    do: schema |> column_definitions("content_modules") |> Enum.filter(&(elem(&1, 0) == "write_with_ai"))

  test "adds write_with_ai to modules in public and every environment, off in existing ones, and removes it" do
    expected = write_with_ai("public")
    query!("ALTER TABLE content_modules DROP COLUMN write_with_ai")
    create_environment(@tenant, ["content_modules"])

    modules =
      Map.new(["public", @tenant], fn schema ->
        [[id]] =
          rows("""
          INSERT INTO "#{schema}".content_modules
            (uid, name, namespace, help_text, class, code, type, sequence, inserted_at, updated_at)
          VALUES ('m218', '{"en": "Text"}', '{"en": "general"}', '{"en": ""}', 'text', '', 'liquid', 0, NOW(), NOW())
          RETURNING id
          """)

        {schema, id}
      end)

    version = up(@template)

    for schema <- ["public", @tenant] do
      assert write_with_ai(schema) == expected
    end

    for {schema, id} <- modules do
      assert rows(~s(SELECT class, write_with_ai FROM "#{schema}".content_modules WHERE id = $1), [id]) ==
               [["text", false]]
    end

    down(@template, version)

    for schema <- ["public", @tenant], do: assert(write_with_ai(schema) == [])
  end
end

defmodule Brando.Migrations.Brando234TranslateVarInstructionsTest do
  # Runs the upgrade template inside the sandbox transaction, with the column
  # turned back into text first; Postgres DDL is transactional, so everything
  # is undone.
  use ExUnit.Case
  use Brando.ConnCase

  import Brando.MigrationTemplates

  @template "brando_234_translate_var_instructions.exs"
  @tenant "tenant_acme_staging"

  defp type(schema) do
    [[type]] =
      rows(
        "SELECT data_type FROM information_schema.columns " <>
          "WHERE table_schema = $1 AND table_name = 'content_vars' AND column_name = 'instructions'",
        [schema]
      )

    type
  end

  defp insert!(schema, key, instructions) do
    query!(
      ~s|INSERT INTO "#{schema}".content_vars (key, type, instructions, inserted_at, updated_at) VALUES ($1, 'string', $2, now(), now())|,
      [key, instructions]
    )
  end

  defp instructions(schema) do
    schema
    |> then(&rows(~s|SELECT key, instructions FROM "#{&1}".content_vars WHERE key LIKE 'brando234-%' ORDER BY key|))
    |> Enum.map(&List.to_tuple/1)
  end

  test "keeps each var's instructions under the default language, in public and every environment" do
    query!("ALTER TABLE public.content_vars ALTER COLUMN instructions TYPE text USING instructions ->> 'en'")
    create_environment(@tenant, ["content_vars"])
    language = to_string(Application.get_env(:brando, :default_language) || "en")

    for schema <- ["public", @tenant] do
      assert type(schema) == "text"
      insert!(schema, "brando234-a", "Short and plain")
      insert!(schema, "brando234-b", "  ")
      insert!(schema, "brando234-c", nil)
    end

    version = up(@template)

    for schema <- ["public", @tenant] do
      assert type(schema) == "jsonb"

      assert instructions(schema) == [
               {"brando234-a", %{language => "Short and plain"}},
               {"brando234-b", nil},
               {"brando234-c", nil}
             ]
    end

    # Running it again changes nothing
    up(@template)
    assert instructions("public") |> hd() == {"brando234-a", %{language => "Short and plain"}}

    query!(~s|UPDATE public.content_vars SET instructions = '{"xx": "Only this one"}' WHERE key = 'brando234-b'|)

    down(@template, version)

    for schema <- ["public", @tenant], do: assert(type(schema) == "text")

    assert instructions("public") == [
             {"brando234-a", "Short and plain"},
             {"brando234-b", "Only this one"},
             {"brando234-c", nil}
           ]
  end
end

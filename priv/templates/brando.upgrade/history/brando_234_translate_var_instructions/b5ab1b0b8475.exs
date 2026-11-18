defmodule Brando.Repo.Migrations.Brando234TranslateVarInstructions do
  use Ecto.Migration

  @moduledoc """
  A var's instructions become a language map (`%{"en" => "Short and
  plain", "no" => "Kort og enkelt"}`), like its label, so editors read them
  in their admin language. In every site environment, each existing text is
  kept under the default language; `down` keeps that language's text, else
  any. A column already converted is left as it is.
  """

  def up do
    for prefix <- prefixes(), column_type(prefix) == "text" do
      execute("""
      ALTER TABLE "#{prefix}".content_vars ALTER COLUMN instructions TYPE jsonb USING
        CASE WHEN instructions IS NULL OR btrim(instructions) = '' THEN NULL
             ELSE jsonb_build_object('#{language()}', instructions) END
      """)
    end
  end

  def down do
    # No subquery: Postgres refuses one in a USING clause. The first value of
    # the map is taken with a jsonpath function instead.
    for prefix <- prefixes(), column_type(prefix) == "jsonb" do
      execute("""
      ALTER TABLE "#{prefix}".content_vars ALTER COLUMN instructions TYPE text USING
        coalesce(instructions ->> '#{language()}', jsonb_path_query_first(instructions, '$.*') #>> '{}')
      """)
    end
  end

  defp language, do: to_string(Application.get_env(:brando, :default_language) || "en")

  defp column_type(prefix) do
    %{rows: rows} =
      repo().query!(
        "SELECT data_type FROM information_schema.columns " <>
          "WHERE table_schema = $1 AND table_name = 'content_vars' AND column_name = 'instructions'",
        [prefix]
      )

    case rows do
      [[type]] -> type
      [] -> nil
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

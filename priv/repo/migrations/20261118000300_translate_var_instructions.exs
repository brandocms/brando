defmodule BrandoIntegration.Repo.Migrations.TranslateVarInstructions do
  use Ecto.Migration

  # Mirrors the brando_234 upgrade migration for the test schema.
  @moduledoc """
  A var's instructions become a language map, like its label. Each existing
  text is kept under the default language; `down` keeps that language's
  text, else any.
  """

  def up do
    language = to_string(Application.get_env(:brando, :default_language) || "en")

    execute("""
    ALTER TABLE content_vars ALTER COLUMN instructions TYPE jsonb USING
      CASE WHEN instructions IS NULL OR btrim(instructions) = '' THEN NULL
           ELSE jsonb_build_object('#{language}', instructions) END
    """)
  end

  def down do
    language = to_string(Application.get_env(:brando, :default_language) || "en")

    execute("""
    ALTER TABLE content_vars ALTER COLUMN instructions TYPE text USING
      coalesce(instructions ->> '#{language}', jsonb_path_query_first(instructions, '$.*') #>> '{}')
    """)
  end
end

defmodule BrandoIntegration.Repo.Migrations.TranslateVarLabels do
  use Ecto.Migration

  # Mirrors the brando_190 upgrade migration for the test schema.
  @moduledoc """
  A var's label becomes a language map (`%{"en" => "Size", "no" => "Størrelse"}`),
  like a module's name, so editors see it in their admin language. Each
  existing label is kept under the default language; `down` keeps that
  language's text, else any.
  """

  def up do
    language = to_string(Application.get_env(:brando, :default_language) || "en")

    execute("""
    ALTER TABLE content_vars ALTER COLUMN label TYPE jsonb USING
      CASE WHEN label IS NULL OR btrim(label) = '' THEN NULL
           ELSE jsonb_build_object('#{language}', label) END
    """)
  end

  def down do
    language = to_string(Application.get_env(:brando, :default_language) || "en")

    # No subquery: Postgres refuses one in a USING clause ("cannot use
    # subquery in transform expression"). The first value of the map is
    # taken with a jsonpath function instead.
    execute("""
    ALTER TABLE content_vars ALTER COLUMN label TYPE text USING
      coalesce(label ->> '#{language}', jsonb_path_query_first(label, '$.*') #>> '{}')
    """)
  end
end

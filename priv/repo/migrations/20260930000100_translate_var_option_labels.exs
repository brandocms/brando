defmodule BrandoIntegration.Repo.Migrations.TranslateVarOptionLabels do
  use Ecto.Migration

  # Mirrors the brando_191 upgrade migration for the test schema.
  @moduledoc """
  A select var's options get language maps for labels too
  (`%{"en" => "Center", "no" => "Midtstilt"}`), like the var's own label
  (brando_190). Each existing option label is kept under the default language;
  `down` keeps that language's text, else any.
  """

  def up do
    language = to_string(Application.get_env(:brando, :default_language) || "en")

    execute("""
    UPDATE content_vars SET options = (
      SELECT jsonb_agg(
        CASE WHEN jsonb_typeof(o -> 'label') = 'string'
             THEN jsonb_set(o, '{label}', jsonb_build_object('#{language}', o ->> 'label'))
             ELSE o END
        ORDER BY ord)
      FROM jsonb_array_elements(options) WITH ORDINALITY AS t(o, ord)
    )
    WHERE jsonb_typeof(options) = 'array' AND jsonb_array_length(options) > 0
    """)
  end

  def down do
    language = to_string(Application.get_env(:brando, :default_language) || "en")

    execute("""
    UPDATE content_vars SET options = (
      SELECT jsonb_agg(
        CASE WHEN jsonb_typeof(o -> 'label') = 'object'
             THEN jsonb_set(o, '{label}', to_jsonb(coalesce(
               o -> 'label' ->> '#{language}',
               (SELECT value FROM jsonb_each_text(o -> 'label') LIMIT 1),
               '')))
             ELSE o END
        ORDER BY ord)
      FROM jsonb_array_elements(options) WITH ORDINALITY AS t(o, ord)
    )
    WHERE jsonb_typeof(options) = 'array' AND jsonb_array_length(options) > 0
    """)
  end
end

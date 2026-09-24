defmodule Brando.Repo.Migrations.Brando180TranslateImageTexts do
  use Ecto.Migration

  @moduledoc """
  Test/e2e mirror of `priv/templates/brando.upgrade/migrations/brando_180_*`.
  """

  @columns ~w(alt title credits)

  def up do
    language = default_language()

    for column <- @columns do
      execute """
      ALTER TABLE images ALTER COLUMN #{column} TYPE jsonb USING
        CASE WHEN #{column} IS NULL OR btrim(#{column}) = '' THEN NULL
             ELSE jsonb_build_object('#{language}', #{column}) END
      """
    end
  end

  # The default language's text, else any language's, back to a string.
  # A USING expression cannot hold the subquery, so it goes through a
  # temporary column.
  def down do
    language = default_language()

    for column <- @columns do
      execute "ALTER TABLE images ADD COLUMN #{column}_text text"

      execute """
      UPDATE images SET #{column}_text = COALESCE(
        #{column} ->> '#{language}',
        (SELECT value FROM jsonb_each_text(#{column}) WHERE value <> '' LIMIT 1))
      WHERE #{column} IS NOT NULL
      """

      execute "ALTER TABLE images DROP COLUMN #{column}"
      execute "ALTER TABLE images RENAME COLUMN #{column}_text TO #{column}"
    end
  end

  defp default_language do
    language = to_string(Brando.config(:default_language) || "en")

    # It is interpolated into SQL, so it had better look like a language code.
    unless Regex.match?(~r/^[a-z]{2,3}(-[A-Za-z]{2,4})?$/, language),
      do: raise(ArgumentError, "unexpected default language #{inspect(language)}")

    language
  end
end

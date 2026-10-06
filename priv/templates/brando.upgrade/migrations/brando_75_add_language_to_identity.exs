defmodule Brando.Repo.Migrations.AddLanguageToIdentity do
  use Ecto.Migration

  # The site's single identity row becomes the default language's, and is
  # copied to every other configured language: each language needs its own.
  def up do
    rename table(:sites_identity), to: table(:sites_identities)

    alter table(:sites_identities) do
      add :language, :text, default: default_language()
    end

    flush()

    for language <- languages(), language != default_language() do
      copy_to_language("sites_identities", language)
    end
  end

  def down do
    execute "DELETE FROM sites_identities WHERE language <> '#{default_language()}'"

    alter table(:sites_identities) do
      remove :language
    end

    rename table(:sites_identities), to: table(:sites_identity)
  end

  defp copy_to_language(table, language) do
    columns =
      repo().query!(
        """
        SELECT column_name FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = $1
          AND column_name NOT IN ('id', 'language')
        ORDER BY ordinal_position
        """,
        [table]
      ).rows
      |> List.flatten()
      |> Enum.map_join(", ", &~s("#{&1}"))

    execute """
    INSERT INTO #{table} (language, #{columns})
    SELECT '#{language}', #{columns} FROM #{table}
    WHERE language = '#{default_language()}'
    """
  end

  defp languages do
    (Brando.config(:languages) || [])
    |> Enum.map(&to_string(&1[:value]))
    |> Enum.filter(&valid_language?/1)
  end

  defp default_language do
    language = to_string(Brando.config(:default_language) || "en")

    # It is interpolated into SQL, so it had better look like a language code.
    unless valid_language?(language),
      do: raise(ArgumentError, "unexpected default language #{inspect(language)}")

    language
  end

  defp valid_language?(language), do: Regex.match?(~r/^[a-z]{2,3}(-[A-Za-z]{2,4})?$/, language)
end

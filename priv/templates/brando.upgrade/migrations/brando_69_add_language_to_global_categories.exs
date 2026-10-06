defmodule Brando.Repo.Migrations.AddLanguageToGlobalCategories do
  use Ecto.Migration

  # Existing global categories belong to the site's default language.
  def change do
    alter table(:sites_global_categories) do
      add :language, :text, default: default_language()
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

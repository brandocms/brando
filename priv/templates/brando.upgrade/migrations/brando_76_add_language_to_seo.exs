defmodule Brando.Repo.Migrations.AddLanguageToSEO do
  use Ecto.Migration

  def change do
    rename table(:sites_seo), to: table(:sites_seos)

    alter table(:sites_seos) do
      add :language, :text, default: "en"
    end
  end
end

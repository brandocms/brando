defmodule Brando.Repo.Migrations.AddLanguageToGlobalCategories do
  use Ecto.Migration

  def change do
    alter table(:sites_global_categories) do
      add :language, :text, default: "en"
    end
  end
end

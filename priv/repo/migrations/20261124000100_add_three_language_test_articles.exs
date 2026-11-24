defmodule BrandoIntegration.Repo.Migrations.AddThreeLanguageTestArticles do
  use Ecto.Migration

  @moduledoc """
  Test articles in three languages (`Brando.ThreeLanguageTest`, test/support):
  a version linked to another version's source.
  """

  def change do
    create table(:three_language_articles) do
      add :title, :text
      add :slug, :text
      add :language, :text
      add :status, :integer
      add :creator_id, references(:users)
      add :updated_by_id, references(:users, on_delete: :nilify_all)
      add :edited_at, :utc_datetime
      add :deleted_at, :utc_datetime
      timestamps()
    end

    create table(:three_language_articles_alternates) do
      add :entry_id, references(:three_language_articles, on_delete: :delete_all)
      add :linked_entry_id, references(:three_language_articles, on_delete: :delete_all)
      timestamps()
    end

    create unique_index(:three_language_articles_alternates, [:entry_id, :linked_entry_id])
  end
end

defmodule BrandoIntegration.Repo.Migrations.AddFragmentAlternates do
  use Ecto.Migration

  # Mirrors the brando_244 upgrade migration for the test schema.
  @moduledoc """
  Language links between fragments (`Brando.Pages.Fragment.Alternate`), as
  `pages_alternates` links pages.
  """

  def change do
    create table(:pages_fragments_alternates) do
      add :entry_id, references(:pages_fragments, on_delete: :delete_all)
      add :linked_entry_id, references(:pages_fragments, on_delete: :delete_all)
      timestamps()
    end

    create unique_index(:pages_fragments_alternates, [:entry_id, :linked_entry_id])

    # Language versions matched by key behind a record policy, for the
    # form's lists of them (`Brando.AuthorizationTestResources.Snippet`)
    create table(:authorization_test_snippets) do
      add :title, :text
      add :key, :text
      add :language, :text
      add :creator_id, references(:users, on_delete: :nilify_all)
      timestamps()
    end

    create table(:authorization_test_snippets_alternates) do
      add :entry_id, references(:authorization_test_snippets, on_delete: :delete_all)
      add :linked_entry_id, references(:authorization_test_snippets, on_delete: :delete_all)
      timestamps()
    end

    create unique_index(:authorization_test_snippets_alternates, [:entry_id, :linked_entry_id])

    # Synchronized articles with a required category that has language links
    # (`Brando.SyncCategoryTest`)
    create table(:synctest_categories) do
      add :title, :text
      add :language, :text
      timestamps()
    end

    create table(:synctest_categories_alternates) do
      add :entry_id, references(:synctest_categories, on_delete: :delete_all)
      add :linked_entry_id, references(:synctest_categories, on_delete: :delete_all)
      timestamps()
    end

    create unique_index(:synctest_categories_alternates, [:entry_id, :linked_entry_id])

    create table(:synctest_categorized_articles) do
      add :title, :text
      add :language, :text
      add :status, :integer
      add :category_id, references(:synctest_categories), null: false
      add :page_id, references(:pages, on_delete: :nilify_all)
      add :creator_id, references(:users)
      add :updated_by_id, references(:users, on_delete: :nilify_all)
      add :edited_at, :utc_datetime
      timestamps()
    end

    create table(:synctest_categorized_articles_alternates) do
      add :entry_id, references(:synctest_categorized_articles, on_delete: :delete_all)
      add :linked_entry_id, references(:synctest_categorized_articles, on_delete: :delete_all)
      timestamps()
    end

    create unique_index(:synctest_categorized_articles_alternates, [:entry_id, :linked_entry_id])
  end
end

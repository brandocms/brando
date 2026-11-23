defmodule BrandoIntegration.Repo.Migrations.AddSlugScopeTestArticles do
  use Ecto.Migration

  @moduledoc """
  Synchronized test articles whose slug is unique per language or across the
  table (`Brando.SlugScopeTest`): the slug a new translation gets.
  """

  def change do
    for table <- [:slug_scope_language_articles, :slug_scope_table_articles] do
      create table(table) do
        add :title, :text
        add :slug, :text
        add :language, :text
        add :status, :integer
        add :creator_id, references(:users)
        add :updated_by_id, references(:users, on_delete: :nilify_all)
        add :edited_at, :utc_datetime
        timestamps()
      end

      create table(:"#{table}_alternates") do
        add :entry_id, references(table, on_delete: :delete_all)
        add :linked_entry_id, references(table, on_delete: :delete_all)
        timestamps()
      end

      create unique_index(:"#{table}_alternates", [:entry_id, :linked_entry_id])
    end

    create unique_index(:slug_scope_language_articles, [:slug, :language])
    create unique_index(:slug_scope_table_articles, [:slug])
  end
end

defmodule BrandoIntegration.Repo.Migrations.AddRichtextrowsTables do
  use Ecto.Migration

  # The rich-text rows test blueprints (Brando.RichTextRows.*): a moved
  # identifier's links are looked for in every Blueprint with a table, these
  # included, so each needs its table.
  def change do
    create table(:richtextrows_entries) do
      add :title, :text
      add :intro, :text
      add :quotes, :jsonb
      add :feature, :jsonb
    end

    create table(:richtextrows_items) do
      add :label, :text
      add :text, :text
      add :sequence, :integer
      add :entry_id, references(:richtextrows_entries, on_delete: :delete_all)
    end

    create table(:richtextrows_checked_items) do
      add :text, :text
      add :entry_id, references(:richtextrows_entries, on_delete: :delete_all)
    end

    create table(:richtextrows_plains) do
      add :title, :text
      add :text, :text
      add :quotes, :jsonb
    end

    create table(:richtextrows_disagreeings) do
      add :title, :text
      add :intro, :text
      add :aside, :text
    end
  end
end

defmodule BrandoIntegration.Repo.Migrations.KeepTranslationSourcePreviousTexts do
  use Ecto.Migration

  # Mirrors the brando_239 upgrade migration for the test schema.
  @moduledoc """
  The source's texts of a translation's last sync, and a review's previous
  source text.
  """

  def change do
    alter table(:translation_group_members) do
      add :baseline_texts, :map, null: false, default: %{}
    end

    alter table(:translation_work_items) do
      add :source_previous, :text
    end
  end
end

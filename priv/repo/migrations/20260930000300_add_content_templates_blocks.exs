defmodule BrandoIntegration.Repo.Migrations.AddContentTemplatesBlocks do
  use Ecto.Migration

  # Content templates have blocks like any entry. Sites get this join table
  # from the brando_103 upgrade migration; the test schema never had it.
  def change do
    create table(:content_templates_blocks) do
      add :entry_id, references(:content_templates, on_delete: :delete_all)
      add :block_id, references(:content_blocks, on_delete: :delete_all)
      add :sequence, :integer
    end

    create unique_index(:content_templates_blocks, [:entry_id, :block_id])
  end
end

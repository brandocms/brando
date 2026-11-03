defmodule BrandoIntegration.Repo.Migrations.AddInlineRowRelatedEntries do
  use Ecto.Migration

  # An `:entries` input in a subform row of the E2E client form
  # (`E2eProject.Projects.InlineRow`, masked-entries.spec.js).
  def change do
    create table(:projects_inline_rows_related_entries_identifiers) do
      add :parent_id, references(:projects_inline_rows, on_delete: :delete_all)
      add :identifier_id, references(:content_identifiers, on_delete: :delete_all)
      add :sequence, :integer
      timestamps()
    end

    create unique_index(:projects_inline_rows_related_entries_identifiers, [:parent_id, :identifier_id],
             name: :projects_inline_rows_related_entries_identifiers_uniq
           )
  end
end

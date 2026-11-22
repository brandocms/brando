defmodule BrandoIntegration.Repo.Migrations.AddProposalToPreviews do
  use Ecto.Migration

  # Mirrors the brando_241 upgrade migration for the test schema.
  @moduledoc """
  `sites_previews.proposal_id`: the proposal version a connected AI tool's
  preview link shows.
  """

  def change do
    alter table(:sites_previews, prefix: "public") do
      add :proposal_id, references(:content_proposals, type: :binary_id, prefix: "public", on_delete: :delete_all)
    end

    create index(:sites_previews, [:proposal_id], prefix: "public")
  end
end

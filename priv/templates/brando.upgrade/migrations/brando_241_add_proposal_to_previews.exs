defmodule Brando.Repo.Migrations.Brando241AddProposalToPreviews do
  use Ecto.Migration

  @moduledoc """
  `sites_previews.proposal_id`: the proposal version a connected AI tool's
  preview link shows (`preview_proposal`). Such a link opens only while that
  version is under review. Empty for every existing preview and for an
  editor's shareable link.
  """

  def up do
    alter table(:sites_previews, prefix: "public") do
      add_if_not_exists :proposal_id,
                        references(:content_proposals, type: :binary_id, prefix: "public", on_delete: :delete_all)
    end

    create_if_not_exists index(:sites_previews, [:proposal_id], prefix: "public")
  end

  def down do
    drop_if_exists index(:sites_previews, [:proposal_id], prefix: "public")

    alter table(:sites_previews, prefix: "public") do
      remove_if_exists :proposal_id, :binary_id
    end
  end
end

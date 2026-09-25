defmodule Brando.Repo.Migrations.Brando183AddContentProposalReceipts do
  use Ecto.Migration

  @moduledoc """
  Receipts for applied content proposals (`Brando.Content.Proposals`).

  A receipt is written in the same transaction as the content it records, so
  applying a proposal a second time finds it and changes nothing. Like
  content-transfer receipts it lives in `public`, scoped by site and
  environment, and is not copied between environments.
  """

  def change do
    create table(:content_proposal_receipts, primary_key: false, prefix: "public") do
      add :id, :uuid, primary_key: true
      add :version, :integer, null: false
      add :scope, :text, null: false
      add :actor_id, references(:users, prefix: "public", on_delete: :nilify_all)
      add :before, :map, null: false
      add :after, :map, null: false
      add :mappings, :map, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:content_proposal_receipts, [:scope, :actor_id, :inserted_at], prefix: "public")
  end
end

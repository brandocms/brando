defmodule Brando.Repo.Migrations.Brando184AddContentProposals do
  use Ecto.Migration

  @moduledoc """
  Stored, versioned content proposals (`Brando.Content.Proposals.Record`).

  Approving and applying refer to one immutable version. Like proposal
  receipts they live in `public`, scoped by site and environment.
  """

  def change do
    create table(:content_proposals, primary_key: false, prefix: "public") do
      add :id, :uuid, primary_key: true
      add :conversation_id, :uuid
      add :version, :integer, null: false
      add :supersedes_id, :uuid
      add :scope, :text, null: false
      add :actor_id, references(:users, prefix: "public", on_delete: :nilify_all)
      add :summary, :text
      add :operations, {:array, :map}, null: false
      add :fingerprints, :map, null: false
      add :module_versions, {:array, :map}, null: false
      add :problems, {:array, :map}, null: false
      add :effects, :map, null: false
      add :status, :text, null: false, default: "pending"
      add :approved_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:content_proposals, [:scope, :actor_id, :inserted_at], prefix: "public")
    create index(:content_proposals, [:conversation_id], prefix: "public")
  end
end

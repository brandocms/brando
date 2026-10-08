defmodule BrandoIntegration.Repo.Migrations.AddProposalsToActivityEvents do
  use Ecto.Migration

  # Mirrors the brando_216 upgrade migration for the test schema.
  @moduledoc """
  The proposal a change came from and the user who approved it, on the
  activity log (`Brando.Activity.Event`).
  """

  def change do
    alter table(:activity_events) do
      add :proposal_id, :uuid
      add :approver_id, references(:users, prefix: "public", on_delete: :nilify_all)
    end

    create index(:activity_events, [:proposal_id])
  end
end

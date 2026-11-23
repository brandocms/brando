defmodule BrandoIntegration.Repo.Migrations.AddAutoApplyToMCPGrants do
  use Ecto.Migration

  # Mirrors the brando_247 upgrade migration for the test schema.
  @moduledoc """
  What a connection may apply without review (`mcp_grants.auto_apply`), who
  set it and when; and on a proposal, the connection it was applied
  automatically under, or why it was not.
  """

  def change do
    alter table(:mcp_grants) do
      add :auto_apply, :text, null: false, default: "none"
      add :auto_apply_set_by_id, references(:users, on_delete: :nilify_all)
      add :auto_apply_set_at, :utc_datetime_usec
    end

    alter table(:content_proposals) do
      add :auto_applied_grant_id, :bigint
      add :auto_apply_reason, :text
    end
  end
end

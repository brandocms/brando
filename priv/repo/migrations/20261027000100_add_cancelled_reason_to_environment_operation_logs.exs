defmodule BrandoIntegration.Repo.Migrations.AddCancelledReasonToEnvironmentOperationLogs do
  use Ecto.Migration

  # Mirrors the brando_223 upgrade migration for the test schema.
  @moduledoc """
  `environment_operation_logs.cancelled_reason`: why a scheduled operation
  was cancelled when it was due (`Brando.Environments.cancel_unauthorized/3`).
  """

  def change do
    alter table(:environment_operation_logs, prefix: "public") do
      add :cancelled_reason, :text
    end
  end
end

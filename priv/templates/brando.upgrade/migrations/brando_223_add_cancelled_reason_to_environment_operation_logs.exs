defmodule Brando.Repo.Migrations.Brando223AddCancelledReasonToEnvironmentOperationLogs do
  use Ecto.Migration

  @moduledoc """
  `environment_operation_logs.cancelled_reason`: why a scheduled copy or live
  switch was cancelled when it was due instead of run, which the
  Environments screen shows in its operation log. Empty for an operation
  that ran.
  """

  def up do
    alter table(:environment_operation_logs, prefix: "public") do
      add_if_not_exists :cancelled_reason, :text
    end
  end

  def down do
    alter table(:environment_operation_logs, prefix: "public") do
      remove_if_exists :cancelled_reason, :text
    end
  end
end

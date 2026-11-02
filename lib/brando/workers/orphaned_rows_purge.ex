defmodule Brando.Worker.OrphanedRowsPurge do
  @moduledoc """
  Deletes rows left behind by sites, environments and forms deleted before their
  deletion took those rows with it. It deletes personal data for good and never
  runs by itself: an operator reads `report/0` and queues what it names.

      Brando.Worker.OrphanedRowsPurge.report()
      Brando.Worker.OrphanedRowsPurge.purge_deleted_environments()
      Brando.Worker.OrphanedRowsPurge.purge_form_submissions("tenant_acme_production", ["contact"])

  Rows of a deleted site or environment are selected for you. A form's are not:
  copying an environment over another replaces its forms but keeps its
  submissions, so a key with no form may be one the next copy brings back. So
  they are named by key, and a key with a form in that environment is skipped
  when the job runs (`Brando.Forms.purge_submissions_of_deleted_form/1`).
  """
  use Oban.Worker, queue: :default, max_attempts: 2

  require Logger

  alias Brando.Tenant.Job, as: TenantJob
  alias Brando.Tenant.ScopedRows

  @doc """
  What could be purged, deleting nothing: `:environments` from
  `Brando.Tenant.ScopedRows.orphaned/0`, and `:forms` with the keys without a form
  in each active environment, as `%{scope:, key:, count:}`.
  """
  def report do
    %{
      environments: ScopedRows.orphaned(),
      forms: :all |> TenantJob.each_active_environment(&Brando.Forms.submissions_without_form/0) |> List.flatten()
    }
  end

  @doc "Queues deleting the rows of every deleted site and environment."
  def purge_deleted_environments, do: %{"environments" => true} |> new() |> Oban.insert()

  @doc "Queues deleting the submissions of `keys` in the environment `scope` (nil without tenancy)."
  def purge_form_submissions(scope, keys) when is_list(keys) do
    %{"form_keys" => keys, "tenant_prefix" => scope} |> new() |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"environments" => true}}) do
    scopes = ScopedRows.delete_orphaned()
    Logger.info("==> Deleted the rows of #{length(scopes)} deleted environments")
    :ok
  end

  def perform(%Oban.Job{args: %{"form_keys" => keys} = args}) do
    TenantJob.run_current(args, fn ->
      purged = keys |> Enum.map(&Brando.Forms.purge_submissions_of_deleted_form/1) |> Enum.sum()
      Logger.info("==> Deleted #{purged} submissions of deleted forms")
      :ok
    end)
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)
end

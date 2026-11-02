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
  when the job runs (`Brando.Forms.purge_orphaned_submissions/1`), as is a row of
  a form since renamed. With tenancy the job holds the environment operation lock,
  so it never runs during a copy, when `forms` can be briefly empty.

  A form's job that does not name an environment this site has is cancelled, not
  guessed at: a scope without tenancy, none with tenancy, or a scope no registered
  environment has.
  """
  use Oban.Worker, queue: :default, max_attempts: 2

  require Logger

  alias Brando.Environments
  alias Brando.Tenant
  alias Brando.Tenant.Job, as: TenantJob
  alias Brando.Tenant.Registry
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
    case {Tenant.enabled?(), args["tenant_prefix"]} do
      {false, nil} -> purge_forms(keys)
      {false, _prefix} -> {:cancel, :tenant_prefix_without_tenancy}
      {true, nil} -> {:cancel, :missing_tenant_prefix}
      {true, prefix} -> purge_forms_in_environment(prefix, args, keys)
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)

  defp purge_forms_in_environment(prefix, args, keys) do
    case site_of(prefix) do
      nil -> {:cancel, :unregistered_tenant_prefix}
      site -> Environments.with_site_lock(site, fn -> purge_forms_under_lock(prefix, args, keys) end)
    end
  end

  # The environment may be gone once the lock is ours
  defp purge_forms_under_lock(prefix, args, keys) do
    if site_of(prefix),
      do: TenantJob.run(args, fn -> purge_forms(keys) end),
      else: {:cancel, :unregistered_tenant_prefix}
  end

  defp site_of(prefix) do
    with site_key when is_binary(site_key) <- Tenant.site_key_of(prefix),
         %{} = site <- Registry.get_site_by_key(site_key),
         true <- Enum.any?(site.environments, &(Tenant.prefix(site, &1) == prefix)) do
      site
    else
      _ -> nil
    end
  end

  defp purge_forms(keys) do
    purged = Brando.Forms.purge_orphaned_submissions(keys)
    Logger.info("==> Deleted #{purged} submissions of deleted forms")
    :ok
  end
end

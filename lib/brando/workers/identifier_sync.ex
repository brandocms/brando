defmodule Brando.Worker.IdentifierSync do
  @moduledoc """
  Syncs one site environment's identifiers (`Brando.Content.Identifier.Sync.sync/1`,
  what `mix brando.identifiers.sync` runs), so their stored URLs follow the
  site's languages. Queued for each environment of a site whose default
  language changes (`Brando.Tenant.Registry.update_site/2`): the default
  language's entries lose their language prefix and the old default's gain
  one.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: :infinity, keys: [:tenant_prefix], states: [:available, :scheduled, :retryable]]

  require Logger

  alias Brando.Tenant.Job, as: TenantJob

  @doc "Queues a sync for each of `site`'s environments."
  @spec enqueue(Brando.Sites.Site.t()) :: :ok
  def enqueue(%Brando.Sites.Site{environments: environments} = site) when is_list(environments) do
    for environment <- environments do
      %{"tenant_prefix" => Brando.Tenant.prefix(site, environment)}
      |> new()
      |> Oban.insert()
    end

    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{} = job) do
    # The job may run on a node whose tenant cache has not yet seen the new
    # default language, which the URLs are built from
    Brando.Tenant.Cache.warm()

    TenantJob.run(job, fn ->
      case Brando.Content.Identifier.Sync.sync() do
        :ok ->
          :ok

        {:error, failures} ->
          Logger.warning(
            "[Brando.Worker.IdentifierSync] #{length(failures)} identifier(s) in " <>
              "#{job.args["tenant_prefix"]} could not be synced"
          )

          :ok
      end
    end)
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(30)
end

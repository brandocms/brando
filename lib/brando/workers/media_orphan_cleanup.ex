defmodule Brando.Worker.MediaOrphanCleanup do
  @moduledoc "Runs conservative cross-environment local media cleanup."

  use Oban.Worker, queue: :upload_reaping, max_attempts: 3

  alias Brando.Media.OrphanCleanup
  alias Brando.Tenant
  alias Brando.Tenant.Registry

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"site_id" => site_id} = args}) do
    case Registry.get_site(site_id) do
      nil ->
        {:cancel, :site_not_found}

      site ->
        run_site(site, args)
    end
  end

  def perform(%Oban.Job{args: args}) do
    if Tenant.enabled?() do
      errors =
        Registry.list_sites()
        |> Enum.map(&run_site(&1, args))
        |> Enum.reject(&(&1 == :ok))

      if errors == [], do: :ok, else: {:error, errors}
    else
      :ok
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(30)

  defp run_site(site, args) do
    opts =
      [
        dry_run: args["dry_run"] == true,
        older_than_seconds: args["older_than_seconds"] || :timer.hours(24) |> div(1_000)
      ]

    case OrphanCleanup.run(site, opts) do
      {:ok, report} ->
        Logger.info(
          "==> [CRON] Media orphan cleanup for #{site.key}: " <>
            "#{length(report.deleted)} orphan(s) #{if report.dry_run, do: "found", else: "deleted"}"
        )

        :ok

      {:error, reason} ->
        {:error, {site.key, reason}}
    end
  end
end

defmodule Brando.Worker.MediaOrphanCleanup do
  @moduledoc """
  Runs conservative local media cleanup (`Brando.Media.OrphanCleanup`).

  With tenancy, every site is cleaned, across its environments. An install
  without tenancy is cleaned only when it asks for it:

      config :brando, media_orphan_cleanup: true

  Such a site can predate the cleanup and keep files of its own under the
  media root that no image or file row knows of; those would go. Look at what
  a run would remove first:

      Brando.Media.OrphanCleanup.run(nil, dry_run: true)
  """

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
      if Brando.config(:media_orphan_cleanup) == true, do: run_site(nil, args), else: :ok
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(30)

  defp label(nil), do: "this site"
  defp label(site), do: site.key

  defp run_site(site, args) do
    opts =
      [
        dry_run: args["dry_run"] == true,
        older_than_seconds: args["older_than_seconds"] || :timer.hours(24) |> div(1_000)
      ]

    case OrphanCleanup.run(site, opts) do
      {:ok, report} ->
        Logger.info(
          "==> [CRON] Media orphan cleanup for #{label(site)}: " <>
            "#{length(report.deleted)} orphan(s) #{if report.dry_run, do: "found", else: "deleted"}"
        )

        :ok

      {:error, reason} ->
        {:error, {label(site), reason}}
    end
  end
end

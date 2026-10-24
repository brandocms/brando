defmodule Brando.Worker.SSGBuild do
  @moduledoc """
  Builds one versioned static artifact under a named tenant environment.

  The build reports to its creator as `BrandoAdmin.Work` under
  `work_key/1`: queued (`Brando.SSG.Builds.request_build/3`), building with
  its count of pages, then ready, deployed or failed. Its deploys and
  rollbacks (`Brando.Worker.SSGDeploy`) report under the same key. The work
  is global: builds belong to no one site's admin.
  """

  use Oban.Worker, queue: :ssg_builds, max_attempts: 3, unique: [period: :infinity, fields: [:args]]
  use Gettext, backend: Brando.Gettext

  alias Brando.SSG.Build
  alias Brando.SSG.Builds
  alias Brando.SSG.Deploy
  alias BrandoAdmin.Work

  # A build waits behind the one before it on the serial queue
  @queued_timeout to_timeout(hour: 1)

  @doc "The `BrandoAdmin.Work` key a build, its deploys and rollbacks report under."
  @spec work_key(pos_integer()) :: String.t()
  def work_key(build_id), do: "static:#{build_id}"

  @doc """
  Reports a build as queued to its creator, before its job is queued: the
  job may run, and report, as soon as it is committed. Not inside a
  caller's transaction, which may still roll the build back.
  """
  @spec report_queued(Build.t()) :: :ok
  def report_queued(%Build{} = build) do
    report(build, fn user, key ->
      Work.start(user, key, gettext("Static build %{version} is queued", version: build.version),
        global: true,
        timeout: @queued_timeout
      )
    end)
  end

  @doc "Reports a build as failed to its creator: its job could not be queued, or the build failed."
  @spec report_failed(Build.t()) :: :ok
  def report_failed(%Build{} = build) do
    report(build, &Work.fail(&1, &2, gettext("Static build %{version} failed", version: build.version), global: true))
  end

  @doc """
  Marks a build's job for its creator's `BrandoAdmin.Work`. The job reports
  its own progress and outcome; tracked, a job Oban gives up on (killed at
  its timeout three times) ends the work as failed. A job lost with its node
  says nothing: its work times out.
  """
  @spec track(Ecto.Changeset.t(), Build.t()) :: Ecto.Changeset.t()
  def track(changeset, %Build{creator_id: nil}), do: changeset

  def track(changeset, %Build{} = build) do
    Work.track(changeset, build.creator_id, work_key(build.id),
      finish: false,
      failed:
        Work.in_locale(build.creator_id, fn -> gettext("Static build %{version} failed", version: build.version) end),
      timeout: @queued_timeout,
      global: true
    )
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"build_id" => build_id}}) do
    case Builds.get_build(build_id) do
      %Build{site: %{status: status}} = build when status != :active ->
        cancel_unbuildable(build, :site_not_active)

      %Build{environment: nil} = build ->
        cancel_unbuildable(build, :environment_not_found)

      %Build{status: status} = build when status in [:queued, :building] ->
        authorize_and_run(build)

      %Build{status: status} when status in [:ready, :deployed, :archived] ->
        :ok

      %Build{status: :failed} ->
        {:cancel, :build_already_failed}

      %Build{} ->
        {:cancel, :build_not_queued}

      nil ->
        {:cancel, :build_not_found}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(30)

  defp authorize_and_run(build) do
    case Brando.Authorization.Operations.authorize(%{id: build.creator_id}, :build, :publishing, build.site_id) do
      :ok -> run_build(build)
      {:error, reason} -> cancel_unbuildable(build, reason)
    end
  end

  defp run_build(build) do
    report(build, fn user, key ->
      Work.update(user, key, gettext("Building static version %{version}", version: build.version), global: true)
    end)

    with {:ok, building} <-
           Builds.update(build, %{
             status: :building,
             build_log: build.build_log <> log_line(build_start_message(build))
           }),
         result <- call_builder(building),
         {:ok, ready} <- finish_build(building, result),
         {:ok, final} <- maybe_deploy(ready),
         :ok <- prune_and_log(final) do
      report(final, &Work.finish(&1, &2, ready_message(final), global: true))
      :ok
    else
      {:error, {:deploy_failed, reason}, ready} -> record_deploy_failure(ready, reason)
      {:error, reason, result} -> fail_build(build, reason, result)
      {:error, reason} -> fail_build(build, reason, %{})
    end
  rescue
    exception ->
      fail_build(build, {:exception, Exception.message(exception)}, %{})
  end

  defp call_builder(build) do
    builder = Application.get_env(:brando, :ssg_builder, Brando.SSG)

    builder.build(build.site, build.environment,
      output_path: build.build_path,
      asset_set: build.asset_set,
      progress: fn
        {:rendering, processed, total, _url}
        when processed == 1 or processed == total or rem(processed, 10) == 0 ->
          Builds.record_progress(build.id, processed - 1, total)

          if build.creator_id,
            do: Work.update(build.creator_id, work_key(build.id), nil, done: processed - 1, total: total, global: true)

        _event ->
          :ok
      end
    )
  end

  defp finish_build(build, {:ok, result}) do
    now = DateTime.utc_now()

    Builds.update(build, %{
      status: :ready,
      built_at: now,
      file_count: result.file_count,
      total_size: result.total_size,
      url_count: result.url_count,
      processed_urls: result.processed_urls,
      failed_urls: result.failed_urls,
      build_log: build.build_log <> log_line("Build completed with #{result.file_count} files")
    })
  end

  defp finish_build(_build, {:error, reason, result}), do: {:error, reason, result}
  defp finish_build(_build, {:error, reason}), do: {:error, reason}
  defp finish_build(_build, result), do: {:error, {:invalid_builder_result, result}}

  defp maybe_deploy(%Build{auto_deploy: true} = build) do
    case Deploy.deploy(build, creator_id: build.creator_id) do
      {:ok, deployed} -> {:ok, deployed}
      {:error, reason} -> {:error, {:deploy_failed, reason}, build}
    end
  end

  defp maybe_deploy(build), do: {:ok, build}

  defp prune_and_log(%Build{site: site, deploy_config: config} = build) do
    case Deploy.prune(site, config["retention_count"] || 10) do
      {:ok, _pruned} ->
        :ok

      {:error, reason} ->
        Builds.append_log(build, "Artifact pruning failed: #{inspect(reason)}")
        :ok
    end
  end

  defp record_deploy_failure(build, reason) do
    Builds.append_log(build, "Automatic deployment failed: #{inspect(reason)}")

    report(build, fn user, key ->
      Work.fail(user, key, gettext("Static build %{version} is ready, but deployment failed", version: build.version),
        global: true
      )
    end)

    {:error, {:deploy_failed, reason}}
  end

  defp fail_build(build, reason, result) do
    current = Builds.get_build(build.id) || build

    attrs = %{
      status: :failed,
      built_at: DateTime.utc_now(),
      file_count: Map.get(result, :file_count, current.file_count),
      total_size: Map.get(result, :total_size, current.total_size),
      url_count: Map.get(result, :url_count, current.url_count),
      processed_urls: Map.get(result, :processed_urls, current.processed_urls),
      failed_urls: Map.get(result, :failed_urls, current.failed_urls),
      build_log: current.build_log <> log_line("Build failed: #{inspect(reason)}")
    }

    case Builds.update(current, attrs) do
      {:ok, failed} ->
        report_failed(failed)
        {:error, reason}

      {:error, changeset} ->
        {:error, {:persist_build_failure_failed, reason, changeset}}
    end
  end

  defp ready_message(%Build{status: :deployed, version: version}),
    do: gettext("Static build %{version} is deployed", version: version)

  defp ready_message(%Build{version: version}), do: gettext("Static build %{version} is ready", version: version)

  # In the creator's language: the job has none of its own
  defp report(%Build{creator_id: nil}, _fun), do: :ok

  defp report(%Build{} = build, fun) do
    creator = if match?(%Brando.Users.User{}, build.creator), do: build.creator, else: build.creator_id
    Work.in_locale(creator, fn -> fun.(build.creator_id, work_key(build.id)) end)
    :ok
  end

  defp cancel_unbuildable(build, reason) do
    Builds.update(build, %{
      status: :failed,
      built_at: DateTime.utc_now(),
      build_log: build.build_log <> log_line("Build cancelled: #{inspect(reason)}")
    })

    report(build, fn user, key ->
      Work.fail(user, key, gettext("Static build %{version} was cancelled", version: build.version), global: true)
    end)

    {:cancel, reason}
  end

  defp log_line(message) do
    timestamp = Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d %H:%M:%S UTC")
    "[#{timestamp}] #{message}\n"
  end

  defp build_start_message(%Build{status: :building}), do: "Build restarted after an interrupted attempt"
  defp build_start_message(%Build{}), do: "Build started"
end

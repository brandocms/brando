defmodule Brando.Worker.SSGBuild do
  @moduledoc "Builds one versioned static artifact under a named tenant environment."

  use Oban.Worker, queue: :ssg_builds, max_attempts: 3, unique: [period: :infinity, fields: [:args]]

  alias Brando.SSG.Build
  alias Brando.SSG.Builds
  alias Brando.SSG.Deploy

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"build_id" => build_id}}) do
    case Builds.get_build(build_id) do
      %Build{site: %{status: status}} = build when status != :active ->
        cancel_unbuildable(build, :site_not_active)

      %Build{environment: nil} = build ->
        cancel_unbuildable(build, :environment_not_found)

      %Build{status: status} = build when status in [:queued, :building] ->
        case Brando.Authorization.Operations.authorize(%{id: build.creator_id}, :build, :publishing, build.site_id) do
          :ok -> run_build(build)
          {:error, reason} -> cancel_unbuildable(build, reason)
        end

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

  defp run_build(build) do
    with {:ok, building} <-
           Builds.update(build, %{
             status: :building,
             build_log: build.build_log <> log_line(build_start_message(build))
           }),
         result <- call_builder(building),
         {:ok, ready} <- finish_build(building, result),
         {:ok, final} <- maybe_deploy(ready),
         :ok <- prune_and_log(final) do
      notify_creator(final, "Static build #{final.version} is #{final.status}", :success)
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
    notify_creator(build, "Static build #{build.version} is ready, but deployment failed", :error)
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
        notify_creator(failed, "Static build #{failed.version} failed", :error)
        {:error, reason}

      {:error, changeset} ->
        {:error, {:persist_build_failure_failed, reason, changeset}}
    end
  end

  defp notify_creator(%Build{creator: nil}, _message, _level), do: :ok

  defp notify_creator(%Build{creator: creator}, message, level) do
    BrandoAdmin.Toast.send_to(creator, message, %{level: level, type: :notification})
  rescue
    _endpoint_unavailable -> :ok
  end

  defp cancel_unbuildable(build, reason) do
    Builds.update(build, %{
      status: :failed,
      built_at: DateTime.utc_now(),
      build_log: build.build_log <> log_line("Build cancelled: #{inspect(reason)}")
    })

    {:cancel, reason}
  end

  defp log_line(message) do
    timestamp = Calendar.strftime(DateTime.utc_now(), "%Y-%m-%d %H:%M:%S UTC")
    "[#{timestamp}] #{message}\n"
  end

  defp build_start_message(%Build{status: :building}), do: "Build restarted after an interrupted attempt"
  defp build_start_message(%Build{}), do: "Build started"
end

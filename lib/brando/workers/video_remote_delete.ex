defmodule Brando.Worker.VideoRemoteDelete do
  @moduledoc """
  Asks a video's provider again to delete a video deleted in Brando with
  `delete_remote_on: :on_delete`, when the provider could not answer the
  first time (`Brando.Videos.Uploader.transient_error?/1`): a purge with
  `:on_delete` never asks the provider, so without this the video would stay
  there for good.

  A transient error fails the job and Oban tries it again, 20 times over
  about twelve days with its default backoff, well inside the 30 days the
  deleted record waits for its purge. Any other answer ends it. So does a
  record restored meanwhile or already purged, and a video another record
  still holds (`Brando.Videos.Uploader.delete_remote/1`).

  One job per video and environment (`unique`, `states: :incomplete`).
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 20,
    unique: [keys: [:tenant_prefix, :video_id], states: :incomplete, period: :infinity]

  alias Brando.Tenant.Job, as: TenantJob
  alias Brando.Videos.Uploader
  alias Brando.Videos.Video

  require Logger

  @doc """
  Whether a `Brando.Videos.Uploader.delete_remote/1` error is worth trying
  again: the provider could not answer (`Brando.Videos.Uploader.transient_error?/1`),
  or the video's holdings could not be read or its lock was busy.
  """
  @spec retry?(term()) :: boolean()
  def retry?(reason), do: reason in [:busy, :holdings_unavailable] or Uploader.transient_error?(reason)

  @doc "Queues the retry of `video`'s delete at its provider, in the current environment."
  @spec enqueue(Video.t()) :: :ok
  def enqueue(%Video{id: id}) do
    case %{"video_id" => id} |> TenantJob.attach() |> new() |> Oban.insert() do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.warning("Video #{id} was deleted, and left at its provider: no retry queued, #{inspect(reason)}")
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{} = job), do: TenantJob.run(job, fn -> perform_tenant(job) end)

  defp perform_tenant(%Oban.Job{args: %{"video_id" => video_id}} = job) do
    case Brando.Repo.get(Video, video_id) do
      %Video{deleted_at: %DateTime{}} = video -> delete(video, job)
      _restored_or_purged -> {:cancel, :not_deleted}
    end
  end

  defp delete(video, job) do
    case Uploader.delete_remote(video) do
      # Another record of it, here or elsewhere; logged where that is told.
      {:error, reason} when reason in [:held_in_this_environment, :held_by_another_site, :held_by_another_environment] ->
        :ok

      {:error, reason} ->
        cond do
          not retry?(reason) ->
            Logger.warning("Video #{video.id} was deleted, and left at its provider: #{inspect(reason)}")
            :ok

          job.attempt >= job.max_attempts ->
            Logger.warning("Video #{video.id} was deleted, and left at its provider after #{job.attempt} tries")
            {:error, reason}

          true ->
            {:error, reason}
        end

      ok ->
        ok
    end
  end
end

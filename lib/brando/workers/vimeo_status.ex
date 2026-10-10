defmodule Brando.Worker.VimeoStatus do
  @moduledoc """
  Polls Vimeo until an uploaded video is available or has failed.

  Vimeo has no webhook for transcode completion — the other providers tell
  Brando when a video is ready; for Vimeo, Brando has to ask. One job per video
  snoozes between checks, backing off as the upload ages: every 15 seconds for
  the first ten minutes, then every minute, every five minutes after an hour,
  and every fifteen after six. A video still not ready after a day is marked
  `:errored`, the same deadline `Brando.Worker.VideoUploadReaper` gives an
  upload that never arrived.

  Transient API errors snooze like any other check, so a Vimeo outage costs
  latency rather than the video.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [keys: [:tenant_prefix, :video_id], states: :incomplete, period: :infinity]

  alias Brando.Tenant.Job, as: TenantJob
  alias Brando.Videos.Uploaders.Vimeo
  alias Brando.Videos.Video

  require Logger

  @deadline_seconds 24 * 60 * 60

  @impl Oban.Worker
  def perform(%Oban.Job{} = job), do: TenantJob.run(job, fn -> perform_tenant(job) end)

  defp perform_tenant(%Oban.Job{args: %{"video_id" => video_id}}) do
    case Brando.Repo.get(Video, video_id) do
      %Video{deleted_at: nil, type: :vimeo_account, status: status} = video
      when status in [:uploading, :processing] ->
        check(video)

      _ ->
        {:cancel, :not_pending}
    end
  end

  defp check(video) do
    case Vimeo.sync(video) do
      {:ok, %Video{status: status}} when status in [:ready, :errored] ->
        :ok

      {:error, :not_found} ->
        give_up(video, "deleted on Vimeo")

      {:error, reason} when reason in [:missing_video_id, :invalid_video_id] ->
        give_up(video, inspect(reason))

      result ->
        if age(video) > @deadline_seconds do
          give_up(video, "not ready after 24 hours (last result: #{inspect(result)})")
        else
          {:snooze, interval(age(video))}
        end
    end
  end

  @doc false
  def interval(age) when age < 600, do: 15
  def interval(age) when age < 3_600, do: 60
  def interval(age) when age < 6 * 3_600, do: 300
  def interval(_age), do: 900

  defp age(%Video{inserted_at: inserted_at}) do
    DateTime.diff(DateTime.utc_now(), to_datetime(inserted_at), :second)
  end

  defp to_datetime(%DateTime{} = datetime), do: datetime
  defp to_datetime(%NaiveDateTime{} = naive), do: DateTime.from_naive!(naive, "Etc/UTC")

  defp give_up(video, why) do
    Logger.warning("Vimeo video #{video.id} marked errored: #{why}")

    with {:ok, creator} <- Brando.Users.get_user(video.creator_id),
         {:ok, updated} <- Brando.Videos.update_video(video, %{status: :errored}, creator) do
      Brando.Assets.ProcessingStatus.broadcast(:video, updated, :done)
      Phoenix.PubSub.broadcast(Brando.pubsub(), "brando:video:#{updated.id}", {updated, [:video, :updated]})
    end

    {:cancel, :gave_up}
  end
end

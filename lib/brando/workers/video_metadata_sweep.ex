defmodule Brando.Worker.VideoMetadataSweep do
  @moduledoc """
  Queues a `Brando.Worker.VideoMetadata` lookup for every video missing its
  thumbnail or title (**Fetch details** in the video library).

  A job rather than a task of the library's LiveView: each lookup is its own
  insert, so a library of thousands takes a while, and an editor leaving the
  page must not cut it short. One waiting sweep per environment.

  The sweep and its lookups are one `BrandoAdmin.Work` for the user, under
  `work_key/0`: it counts the lookups as they end, shown beside the button
  or as a toast elsewhere.
  """
  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:tenant_prefix], states: [:available, :scheduled, :retryable], period: :infinity]

  use Gettext, backend: Brando.Gettext

  alias Brando.Tenant.Job, as: TenantJob
  alias Brando.Videos
  alias BrandoAdmin.Work

  @doc """
  Queues a sweep for `user` in the current environment. Its work is started
  by the caller, so the screen is busy at once; the sweep only ends it if it
  fails (in the caller's language) and hands it on to the lookups. When
  another user's sweep is already waiting, it reports to them, so this
  user's work ends at once.
  """
  @spec enqueue(map() | integer()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(user) do
    # Without tenancy there is no prefix to attach; a nil one gives the
    # uniqueness a key to compare all the same.
    %{"user_id" => user_id(user)}
    |> TenantJob.attach()
    |> Map.put_new("tenant_prefix", nil)
    |> new()
    |> Work.track(user, work_key(), finish: false, failed: gettext("Could not look the videos up"))
    |> Oban.insert()
    |> tap(fn
      # Without an id, the insert lost a race for the lock: whose it is is unknown
      {:ok, %Oban.Job{conflict?: true} = job} ->
        if job.args["user_id"] != user_id(user),
          do: Work.finish(user, work_key(), gettext("The videos are already being looked up"))

      _queued ->
        :ok
    end)
  end

  @doc "The `BrandoAdmin.Work` key the sweep and its lookups report under."
  def work_key, do: "video-metadata"

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}} = job) do
    TenantJob.run(job, fn ->
      video_ids = Videos.list_video_ids_missing_metadata()
      report_start(user_id, length(video_ids), job.attempt)
      {:ok, _count} = Videos.enqueue_metadata(video_ids, user_id, work: work_key())
      :ok
    end)
  end

  # One piece of work for the user, counting the lookups as they end
  defp report_start(user_id, 0, _attempt) do
    Work.finish(user_id, work_key(), Work.in_locale(user_id, fn -> gettext("No videos are missing details") end))
  end

  defp report_start(user_id, count, attempt) do
    Work.in_locale(user_id, fn ->
      message = ngettext("Looking up %{count} video", "Looking up %{count} videos", count)

      if attempt == 1 do
        Work.start(user_id, work_key(), message,
          total: count,
          done: gettext("Thumbnails and titles fetched"),
          failed: gettext("Some videos could not be looked up")
        )
      else
        # A retry counts afresh: what the last attempt queued and is still
        # waiting is counted at once, as a conflict
        Work.update(user_id, work_key(), message, total: count, done: 0)
      end
    end)
  end

  defp user_id(%{id: id}), do: id
  defp user_id(id) when is_integer(id), do: id
end

defmodule Brando.Images.SizeRun do
  @moduledoc false
  # A run of Utilities → Image sizes: **Recreate image sizes** or **Recreate
  # changed images**, from the click to the last image processed.
  #
  # `Brando.Worker.ImageMaintenance` walks the images in batches and queues an
  # `ImageProcessor` job for each image to recreate. The run reports to the
  # admin who started it as `BrandoAdmin.Work` under `work_key/0`, counting each
  # image when its job succeeds or gives up:
  #
  #   * `begin/1`, before the walk is queued, starts the work, open (more
  #     batches may follow) and with nothing counted yet;
  #   * `queue/2`, per batch, adds the batch's images to the count, then
  #     queues them, each tracked as a step that names its image when it fails;
  #   * `close/2`, after the last batch, says there are no more: the work ends
  #     when the last queued image is done, or at once when there were none.
  #
  # Whether a run is going on comes from the jobs, not from that work, which
  # only its admin sees: `running?/0` is true while the walk or any image it
  # queued is waiting or being processed, for every admin, on every node. Its
  # watcher does not count: once the images are done, the run is over, and
  # another can start before the watcher's last look.
  #
  # The jobs are the truth, and the work follows them. Each run has an id, in
  # the walk's arguments and each image job's meta:
  #
  #   * a batch counts the run's images so far, not its own on top, and skips
  #     the images the run already queued, so a retried batch comes out the
  #     same; it also says the run's work again (`BrandoAdmin.Work.resume/4`),
  #     which a node restarted halfway has lost, with the run's failed
  #     images. Those come from the jobs that gave up or were cancelled, and
  #     Oban's Pruner deletes them (after 300 seconds by Brando's default):
  #     work restated later than that, or an image whose job could not be
  #     queued at all, is not counted as failed again;
  #   * an image queued again while the run's job for it waits or is being
  #     processed (the image editor saving a focal point) takes over that
  #     job's place in the run (`carry_over/2`);
  #   * a watcher job (`watch/2`), queued with the walk, waits for the walk and
  #     the run's images, says the work again for a restarted node, and ends
  #     it when they are done and their reports did not: a walk that gave up,
  #     a job cancelled or discarded without running. Such a run failed.
  #
  # Later steps of the same run (re-rendering the entries that show a recreated
  # image) can join its count with `BrandoAdmin.Work.start/4` and `total:`
  # after its walk, before the last image's step is in.
  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]

  alias Brando.Images.Processing
  alias Brando.Tenant.Job, as: TenantJob
  alias Brando.Worker
  alias BrandoAdmin.Work

  @work_key "image-sizes"
  # In each image job's meta, so the run's jobs can be found
  @meta_key "image_size_run"
  @tasks ~w(recreate_sizes recreate_changed_sizes)
  @unfinished_states ~w(available scheduled executing retryable)
  # Images can wait behind other image work; a stalled run is given up later
  @timeout to_timeout(minute: 30)
  # How often the watcher looks, in seconds, and how long it gives the last
  # image's report, sent just after its job is marked done, before ending
  # what is left
  @watch_every 2
  @settle_after 1

  @doc "The `BrandoAdmin.Work` key a run reports under."
  @spec work_key() :: String.t()
  def work_key, do: @work_key

  @doc "The image maintenance tasks that are a run."
  @spec tasks() :: [String.t()]
  def tasks, do: @tasks

  @doc """
  Is a run going on in the current site: its walk unfinished, or
  an image it queued waiting or being processed?
  """
  @spec running?() :: boolean()
  def running?, do: status().running?

  @doc """
  Whether a run is going on (`running?/0`) and how many images it has left
  (`remaining/0`), read once.
  """
  @spec status() :: %{running?: boolean(), remaining: non_neg_integer()}
  def status do
    remaining = remaining()
    %{running?: remaining > 0 or walking?(), remaining: remaining}
  end

  @doc """
  How many images the runs in the current site (or the run `run`) have
  queued and not finished. A job left executing past the image worker's
  timeout is not counted: its node is gone, and Oban's Lifeline may never
  rescue it.
  """
  @spec remaining(String.t() | nil) :: non_neg_integer()
  def remaining(run \\ nil) do
    worker = Oban.Worker.to_string(Worker.ImageProcessor)
    args = TenantJob.attach(%{})
    stale = DateTime.add(DateTime.utc_now(), -Worker.ImageProcessor.timeout(%Oban.Job{}), :millisecond)

    query =
      from j in Oban.Job,
        where:
          j.worker == ^worker and j.state in ^@unfinished_states and
            (j.state != "executing" or j.attempted_at > ^stale) and
            fragment("? @> ?", j.args, ^args),
        select: count(j.id)

    query
    |> of_run(run)
    |> Brando.Repo.one()
  end

  defp of_run(query, nil), do: from(j in query, where: not is_nil(fragment("? -> ?", j.meta, ^@meta_key)))
  defp of_run(query, run), do: from(j in query, where: fragment("? ->> ?", j.meta, ^@meta_key) == ^run)

  # The walk of either task, or `run`'s walk, unfinished. A watcher is not
  # a walk: once its walk and images are done, the run is over, though the
  # watcher has yet to look (and a watcher left executing by a node that is
  # gone holds nothing). A walk left executing past its timeout is not
  # counted, as an image's job is not (`remaining/1`).
  defp walking?(run \\ nil) do
    worker = Oban.Worker.to_string(Worker.ImageMaintenance)
    args = TenantJob.attach(if(run, do: %{"run" => run}, else: %{}))
    stale = DateTime.add(DateTime.utc_now(), -Worker.ImageMaintenance.timeout(%Oban.Job{}), :millisecond)

    query =
      from j in Oban.Job,
        where:
          j.worker == ^worker and j.state in ^@unfinished_states and
            (j.state != "executing" or j.attempted_at > ^stale) and
            fragment("? ->> 'task'", j.args) in ^@tasks and fragment("? @> ?", j.args, ^args) and
            not fragment("? @> ?", j.args, ^%{"watch" => true}),
        select: true,
        limit: 1

    Brando.Repo.one(query) == true
  end

  @doc """
  Starts the run's work for `user`, before its walk is queued, and returns
  the run's id. Work still running under the key belongs to no run (none is
  going on), and is ended.
  """
  @spec begin(Processing.user()) :: String.t()
  def begin(user) do
    if Work.running?(Work.get(user, @work_key)), do: Work.fail(user, @work_key)

    Work.in_locale(user, fn ->
      Work.start(user, @work_key, gettext("Recreating image sizes"), [total: 0, open: true] ++ work_opts())
    end)

    Ecto.UUID.generate()
  end

  defp work_opts do
    [
      timeout: @timeout,
      done: gettext("Image sizes recreated"),
      failed: gettext("Some images could not be recreated")
    ]
  end

  @doc """
  Queues the watcher of the run `run`, whose walk has the arguments `args`
  (`watch/2`).
  """
  @spec queue_watcher(map(), String.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def queue_watcher(args, run) do
    args
    |> Map.merge(%{"run" => run, "watch" => true})
    |> Worker.ImageMaintenance.new(schedule_in: @watch_every)
    |> Oban.insert()
  end

  @doc """
  The watcher's look at its run, `args` its job's arguments: `{:snooze, s}`
  while the walk or any of the run's images is unfinished. Once they are all
  done it looks once more, a moment later, and then ends the run's work if
  it is still running: a report never came.
  """
  @spec watch(map(), Processing.user()) :: :ok | {:snooze, pos_integer()} | {:error, term()}
  def watch(%{"run" => run} = args, user) do
    remaining = remaining(run)

    cond do
      walking?(run) ->
        {:snooze, @watch_every}

      remaining > 0 ->
        # Says nothing new to a node that still has the work. Of the run's
        # finished images, only the failed ones are counted again
        failed = failures(run)
        resume(user, remaining + length(failed), length(failed), false, failed)
        {:snooze, @watch_every}

      args["settle"] ->
        # The run is over as soon as its images are: another may have
        # started since, and the work under the key is that one's
        unless running?(), do: Work.fail(user, @work_key)
        :ok

      true ->
        args
        |> Map.put("settle", true)
        |> Worker.ImageMaintenance.new(schedule_in: @settle_after)
        |> Oban.insert()
        |> case do
          {:ok, _job} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  # The run's work said again: `counted` of `total` done, `failed` the
  # images of those that failed (`failures/1`)
  defp resume(user, total, counted, open, failed) do
    opts = [total: total, counted: counted, open: open, failures: length(failed), failed_items: failed]

    Work.in_locale(user, fn ->
      Work.resume(user, @work_key, gettext("Recreating image sizes"), opts ++ work_opts())
    end)
  end

  # The images of the run's jobs that gave up or were cancelled, oldest
  # first. Oban's Pruner deletes those older than its limit (300 seconds by
  # default): a failure before that is not counted again.
  defp failures(nil), do: []

  defp failures(run) do
    worker = Oban.Worker.to_string(Worker.ImageProcessor)

    Brando.Repo.all(
      from j in Oban.Job,
        where:
          j.worker == ^worker and j.state in ["discarded", "cancelled"] and
            fragment("? ->> ?", j.meta, ^@meta_key) == ^run,
        order_by: [asc: j.id],
        select: fragment("(? ->> 'image_id')::bigint", j.args)
    )
  end

  @doc "Ends the work of a run whose walk could not be queued."
  @spec abort(Processing.user()) :: :ok
  def abort(user), do: Work.fail(user, @work_key)

  @doc """
  Queues each of `images`, of a batch of the run `run:`, to be recreated,
  and counts them in the run's work. `counted:` is how many the run's
  earlier batches counted: the run's count is set, not added to, and images
  the run already queued are skipped, so a batch run again comes out the
  same. `batch:` is the whole batch `images` were picked from: its images
  that an earlier attempt queued and that are no longer picked (processed
  since, they match their config) are counted too. Returns how many it
  counted.
  """
  @spec queue([Processing.image()], Processing.user(), keyword()) :: non_neg_integer()
  def queue(images, user, opts \\ []) do
    run = opts[:run]
    queued = queued(images, run)
    # Queued by an earlier attempt, and no longer picked
    picked = MapSet.new(images, & &1.id)
    earlier = queued(Enum.reject(opts[:batch] || [], &(&1.id in picked)), run)
    count = length(images) + MapSet.size(earlier)
    total = (opts[:counted] || 0) + count

    for image <- images, image.id not in queued do
      prepare = fn changeset -> mark(changeset, user, image, run) end

      case Processing.queue_processing(image, user, [], silent: true, prepare: prepare) do
        {:ok, _job} -> :ok
        # Counted, and never run: it failed
        {:error, _reason} -> Work.advance(user, @work_key, :error, item: image.id)
      end
    end

    # After queueing: a batch that stops halfway has counted nothing, and
    # its retry counts the batch once
    if Work.user_id(user), do: resume(user, total, total - remaining(run), true, failures(run))
    count
  end

  # The images the run has a job for already, in any state
  defp queued(_images, nil), do: MapSet.new()
  defp queued([], _run), do: MapSet.new()

  defp queued(images, run) do
    worker = Oban.Worker.to_string(Worker.ImageProcessor)
    ids = Enum.map(images, &to_string(&1.id))

    from(j in Oban.Job,
      where:
        j.worker == ^worker and fragment("? ->> ?", j.meta, ^@meta_key) == ^run and
          fragment("? ->> 'image_id'", j.args) in ^ids,
      select: fragment("(? ->> 'image_id')::bigint", j.args)
    )
    |> Brando.Repo.all()
    |> MapSet.new()
  end

  @doc """
  An image queued again while a run's job for it is unfinished takes over
  that job's place in the run: `deleted` are the jobs replaced, with their
  `:state` and `:meta`.

  A job replaced while it is being processed still reports its step when
  it ends, and so does the job that takes its place: that image is counted
  twice, and the work can end one image early. The run, read from the
  jobs, goes on until the new job is done.
  """
  @spec carry_over(Ecto.Changeset.t(), [%{state: String.t(), meta: map()}]) :: Ecto.Changeset.t()
  def carry_over(changeset, deleted) do
    case Enum.find(deleted, &(&1.state in @unfinished_states and Map.has_key?(&1.meta || %{}, @meta_key))) do
      nil ->
        changeset

      %{meta: replaced} ->
        meta = Ecto.Changeset.get_field(changeset, :meta) || %{}
        Ecto.Changeset.put_change(changeset, :meta, Map.merge(meta, Map.take(replaced, [@meta_key, Work.meta_key()])))
    end
  end

  @doc """
  No more images: the run ends when the last queued one is done, or at once
  when `queued`, the run's count, is none.
  """
  @spec close(Processing.user(), non_neg_integer()) :: :ok
  def close(user, queued) do
    Work.in_locale(user, fn ->
      done =
        if queued == 0,
          do: gettext("No images to recreate"),
          else: ngettext("%{count} image recreated", "%{count} images recreated", queued)

      Work.close(user, @work_key, done: done)
    end)
  end

  defp mark(changeset, user, image, run) do
    meta = Ecto.Changeset.get_field(changeset, :meta) || %{}

    changeset
    |> Ecto.Changeset.put_change(:meta, Map.put(meta, @meta_key, run || true))
    |> Work.track(user, @work_key, step: true, item: image.id)
  end
end

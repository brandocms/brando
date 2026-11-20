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
  # only its admin sees: `running?/0` is true while the walk, its watcher or
  # any image it queued is waiting or being processed, for every admin, on
  # every node.
  #
  # The jobs are the truth, and the work follows them. Each run has an id, in
  # the walk's arguments and each image job's meta:
  #
  #   * a batch counts the run's images so far, not its own on top, and skips
  #     the images the run already queued, so a retried batch comes out the
  #     same; it also says the run's work again (`BrandoAdmin.Work.resume/4`),
  #     which a node restarted halfway has lost;
  #   * an image queued again while the run's job for it waits (the image
  #     editor saving a focal point) takes over that job's place in the run
  #     (`carry_over/2`);
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
  # A replaced job still waiting hands its place in the run on
  @waiting_states ~w(available scheduled retryable)
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
  Is a run going on in the current site: its walk or watcher unfinished, or
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

  # The walk of either task, or `run`'s walk, unfinished. Without `run`, a
  # watcher counts too.
  defp walking?(run \\ nil) do
    worker = Oban.Worker.to_string(Worker.ImageMaintenance)
    args = TenantJob.attach(if(run, do: %{"run" => run}, else: %{}))

    query =
      from j in Oban.Job,
        where:
          j.worker == ^worker and j.state in ^@unfinished_states and
            fragment("? ->> 'task'", j.args) in ^@tasks and fragment("? @> ?", j.args, ^args),
        select: true,
        limit: 1

    query =
      if run,
        do: from(j in query, where: not fragment("? @> ?", j.args, ^%{"watch" => true})),
        else: query

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
        # Says nothing new to a node that still has the work
        resume(user, remaining, 0, false)
        {:snooze, @watch_every}

      args["settle"] ->
        Work.fail(user, @work_key)

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

  defp resume(user, total, counted, open) do
    Work.in_locale(user, fn ->
      Work.resume(
        user,
        @work_key,
        gettext("Recreating image sizes"),
        [total: total, counted: counted, open: open] ++ work_opts()
      )
    end)
  end

  @doc "Ends the work of a run whose walk could not be queued."
  @spec abort(Processing.user()) :: :ok
  def abort(user), do: Work.fail(user, @work_key)

  @doc """
  Queues each of `images`, a batch of the run `run:`, to be recreated, and
  counts them in the run's work. `counted:` is how many the run's earlier
  batches counted: the run's count is set, not added to, and images the run
  already queued are skipped, so a batch run again comes out the same.
  Returns how many it counted.
  """
  @spec queue([Processing.image()], Processing.user(), keyword()) :: non_neg_integer()
  def queue(images, user, opts \\ []) do
    run = opts[:run]
    total = (opts[:counted] || 0) + length(images)
    queued = queued(images, run)

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
    if Work.user_id(user), do: resume(user, total, total - remaining(run), true)
    length(images)
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
  An image queued again while a run's job for it waits takes over that
  job's place in the run: `deleted` are the jobs replaced, with their
  `:state` and `:meta`. A job already being processed reports itself.
  """
  @spec carry_over(Ecto.Changeset.t(), [%{state: String.t(), meta: map()}]) :: Ecto.Changeset.t()
  def carry_over(changeset, deleted) do
    case Enum.find(deleted, &(&1.state in @waiting_states and Map.has_key?(&1.meta || %{}, @meta_key))) do
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

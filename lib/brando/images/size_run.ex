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
  # A run has a second step: the entries that show its images render again
  # (`Brando.Images.Rerender`). Each image whose processing changed what a
  # render reads queues them, held under the run's key (`hold_key/1`) and
  # tagged with the run's id (`Brando.Content.RenderRun`), so a page that
  # shows many of the run's images renders once. Once the images are done,
  # the watcher releases the key (`images_done/2`) and follows the run's
  # renders, as "Updating pages" with their own count, to the last one
  # (`pages/2`). Only then does the work end, naming both counts: the last
  # image's report does not end it, so a run with a watcher closes it there.
  # A run that dies leaves its held renders to run by themselves at the
  # maximum hold (`Brando.Content.RenderQueue.max_hold/0`).
  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.RenderQueue
  alias Brando.Content.RenderRun
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

  @doc "The key a run's renders are held under (`RenderQueue.enqueue_map/2`)."
  @spec hold_key(String.t()) :: String.t()
  def hold_key(run), do: @work_key <> ":" <> run

  @doc """
  How an image job with `meta` queues the renders of the entries that show
  its image (`Brando.Images.Rerender.after_processing/3`): held under its
  run's key and tagged with the run, for a job of a run; as they are for
  any other.
  """
  @spec render_options(map() | nil) :: keyword()
  def render_options(%{@meta_key => run}) when is_binary(run), do: run_render_options(run)
  def render_options(_meta), do: []

  @doc "How the run `run` queues renders (`render_options/1`): none for no run."
  @spec run_render_options(String.t() | nil) :: keyword()
  def run_render_options(run) when is_binary(run), do: [hold: hold_key(run), run: run]
  def run_render_options(_run), do: []

  @doc "The image maintenance tasks that are a run."
  @spec tasks() :: [String.t()]
  def tasks, do: @tasks

  @doc """
  Is a run going on in the current site: its walk unfinished, an image it
  queued waiting or being processed, or its watcher still to see its pages
  rendered?
  """
  @spec running?() :: boolean()
  def running?, do: status().running?

  @doc """
  Whether a run is going on (`running?/0`), how many images it has left
  (`remaining/0`) and, once those are done, how many pages it has left to
  render, read once.
  """
  @spec status() :: %{running?: boolean(), remaining: non_neg_integer(), pages: non_neg_integer()}
  def status do
    remaining = remaining()

    cond do
      remaining > 0 ->
        %{running?: true, remaining: remaining, pages: 0}

      walking?() ->
        %{running?: true, remaining: 0, pages: 0}

      true ->
        case watching() do
          [] -> %{running?: false, remaining: 0, pages: 0}
          runs -> %{running?: true, remaining: 0, pages: pages_left(runs)}
        end
    end
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
  # a walk (`watching/0`). A walk left executing past its timeout is not
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

  # The runs whose watcher is unfinished: their pages may be left to render.
  # A watcher left executing by a node that is gone holds nothing, and its
  # run's held renders run by themselves.
  defp watching(except \\ nil) do
    worker = Oban.Worker.to_string(Worker.ImageMaintenance)
    args = TenantJob.attach(%{"watch" => true})
    stale = DateTime.add(DateTime.utc_now(), -Worker.ImageMaintenance.timeout(%Oban.Job{}), :millisecond)

    query =
      from j in Oban.Job,
        where:
          j.worker == ^worker and j.state in ^@unfinished_states and
            (j.state != "executing" or j.attempted_at > ^stale) and fragment("? @> ?", j.args, ^args),
        select: fragment("? ->> 'run'", j.args),
        distinct: true

    query |> Brando.Repo.all() |> Enum.reject(&(is_nil(&1) or &1 == except))
  end

  # The entries with a render of `runs` waiting or running, each once. One
  # left executing well past its timeout is not counted (`RenderRun`).
  defp pages_left(runs) do
    worker = "Brando.Worker.EntryRenderer"
    stale = DateTime.add(DateTime.utc_now(), -2, :minute)

    query =
      from j in Oban.Job,
        where:
          j.worker == ^worker and j.state in ^@unfinished_states and
            (j.state != "executing" or j.attempted_at > ^stale) and
            fragment("jsonb_exists_any(? -> 'brando_runs', ?::text[])", j.meta, ^runs) and
            fragment("? ->> 'tenant_prefix' IS NOT DISTINCT FROM ?", j.args, ^Brando.Tenant.current_prefix()),
        select:
          fragment(
            "count(DISTINCT (? ->> 'tenant_prefix', regexp_replace(? ->> 'schema', '^Elixir\\.', ''), ? ->> 'entry_id'))",
            j.args,
            j.args,
            j.args
          )

    Brando.Repo.one(query, prefix: "public")
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
  def watch(%{"pages" => _} = args, user), do: pages(args, user)

  def watch(%{"run" => run} = args, user) do
    remaining = remaining(run)

    cond do
      requeued_walk?(run) ->
        {:snooze, @watch_every}

      walking?(run) ->
        {:snooze, @watch_every}

      remaining > 0 ->
        # Says nothing new to a node that still has the work. Of the run's
        # finished images, only the failed ones are counted again
        failed = failures(run)
        resume(user, remaining + length(failed), length(failed), true, failed)
        {:snooze, @watch_every}

      true ->
        images_done(args, user)
    end
  end

  # The run's walk, left executing past its timeout by a node that is gone,
  # goes back in its queue: the rest of the images are still to be queued,
  # and a batch that runs again counts and queues its images once. Oban's
  # Lifeline does the same an hour later, or never where an app's own Oban
  # config has none, and by then the run would have ended without them. A
  # walk out of attempts is given up, and the run ends as one whose walk did.
  defp requeued_walk?(run) do
    worker = Oban.Worker.to_string(Worker.ImageMaintenance)
    args = TenantJob.attach(%{"run" => run})
    stale = DateTime.add(DateTime.utc_now(), -Worker.ImageMaintenance.timeout(%Oban.Job{}), :millisecond)

    left =
      from j in Oban.Job,
        where:
          j.worker == ^worker and j.state == "executing" and j.attempted_at <= ^stale and
            fragment("? @> ?", j.args, ^args) and not fragment("? @> ?", j.args, ^%{"watch" => true})

    {requeued, _} = Brando.Repo.update_all(from(j in left, where: j.attempt < j.max_attempts), set: [state: "available"])

    Brando.Repo.update_all(from(j in left, where: j.attempt >= j.max_attempts),
      set: [state: "discarded", discarded_at: DateTime.utc_now()]
    )

    requeued > 0
  end

  # The run's walk and images are done: its renders are released, and a
  # moment later, once the last image's report is in, the watcher starts
  # following them (`pages/2`). The work does not end before: the last
  # image's report counts, and an image whose report never came (a walk
  # that gave up, a job cancelled or discarded without running) fails the
  # run at the end.
  defp images_done(%{"run" => run, "settle" => true} = args, user) do
    pages = %{"images" => images(args, user), "images_failed" => images_failed?(args, user), "seen" => %{}}

    args
    |> Map.delete("settle")
    |> Map.put("pages", pages)
    |> pages(user, run)
  end

  defp images_done(%{"run" => run} = args, _user) do
    RenderQueue.release(hold_key(run))

    args
    |> Map.put("settle", true)
    |> Worker.ImageMaintenance.new(schedule_in: @settle_after)
    |> Oban.insert()
    |> case do
      {:ok, _job} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # How many images the run queued: the walk's count, which its last batch
  # gives the watcher (`close/3`), or the work's
  defp images(%{"queued" => queued}, _user) when is_integer(queued), do: queued

  defp images(_args, user) do
    case Work.get(user, @work_key) do
      %Work{total: total} when is_integer(total) -> total
      _ -> 0
    end
  end

  # A walk that never closed (it gave up), an image that failed, or one
  # whose report never came
  defp images_failed?(%{"run" => run} = args, user) do
    work = Work.get(user, @work_key)

    not is_integer(args["queued"]) or failures(run) != [] or
      match?(%Work{failed: failed} when failed > 0, work) or
      match?(%Work{total: total, done: done} when is_integer(total) and done < total, work)
  end

  @doc false
  # The run's second step, one look: releases the run's renders (again: a
  # held render the run queued since is released too) and counts its pages,
  # the entries its renders are for. While any is left, it reports the count
  # and queues its next look, which carries the pages it has seen settle:
  # the Pruner deletes finished jobs (after 300 seconds by Brando's
  # default), and a page counted once stays counted. A page whose render is
  # queued again counts as left until that one settles. When none is left,
  # the work ends, with the images' count and the pages', failed when an
  # image or a page failed.
  @spec pages(map(), Processing.user()) :: :ok | {:error, term()}
  def pages(%{"run" => run} = args, user), do: pages(args, user, run)

  defp pages(%{"pages" => pages} = args, user, run) do
    RenderQueue.release(hold_key(run))

    # This site's: a run's renders are queued in its site
    site = Brando.Tenant.current_prefix()
    states = for {{prefix, _, _}, _} = entry <- RenderRun.render_states(run), prefix == site, into: %{}, do: entry
    left = unsettled(states)
    seen = Map.merge(pages["seen"] || %{}, settled(states))
    seen = Map.drop(seen, left)
    total = map_size(seen) + length(left)
    failed = Enum.count(seen, fn {_entry, outcome} -> outcome == "failed" end)
    # Another run's work is under the key now: this one's watcher was left
    # behind by a node that went down, and is late
    ours? = watching(run) == [] and not walking_other?(run)

    if left == [] do
      if ours?, do: end_run(user, pages, total, failed)
      :ok
    else
      if ours?, do: report_pages(user, run, pages, map_size(seen), total)

      args
      |> Map.put("pages", Map.merge(pages, %{"seen" => seen, "reported" => [map_size(seen), total]}))
      |> Worker.ImageMaintenance.new(schedule_in: @watch_every)
      |> Oban.insert()
      |> case do
        {:ok, _job} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  # As the jobs table holds an entry: the same entry queued as a module or
  # its name is one page
  defp entry_id({prefix, schema, entry_id}), do: Enum.join([prefix || "", schema, entry_id], "|")

  # "done" or "failed" for each entry whose renders have all settled. A
  # render cancelled or given up failed; one left executing by a node that
  # is gone too.
  defp settled(states) do
    for {entry, entry_states} <- states, not Enum.any?(entry_states, &(&1 in @unfinished_states)), into: %{} do
      failed? = Enum.any?(entry_states, &(&1 in ~w(discarded cancelled stale)))
      {entry_id(entry), if(failed?, do: "failed", else: "done")}
    end
  end

  defp unsettled(states) do
    for {entry, entry_states} <- states, Enum.any?(entry_states, &(&1 in @unfinished_states)), do: entry_id(entry)
  end

  defp walking_other?(run) do
    worker = Oban.Worker.to_string(Worker.ImageMaintenance)
    args = TenantJob.attach(%{})

    query =
      from j in Oban.Job,
        where:
          j.worker == ^worker and j.state in ^@unfinished_states and fragment("? @> ?", j.args, ^args) and
            fragment("? ->> 'task'", j.args) in ^@tasks and fragment("? ->> 'run'", j.args) != ^run,
        select: true,
        limit: 1

    Brando.Repo.one(query) == true
  end

  # Says the work again for a node that lost it, then the pages' count,
  # when it changed since the last look
  defp report_pages(user, run, pages, settled, total) do
    if Work.user_id(user), do: Work.in_locale(user, fn -> say_pages(user, run, pages, settled, total) end)
    :ok
  end

  defp say_pages(user, run, pages, settled, total) do
    message = gettext("Updating pages")

    unless Work.running?(Work.get(user, @work_key)) do
      failed = failures(run)
      opts = [total: total, counted: settled, open: true, failures: length(failed), failed_items: failed]
      Work.resume(user, @work_key, message, opts ++ work_opts())
    end

    if pages["reported"] != [settled, total],
      do: Work.update(user, @work_key, message, total: total, done: settled)
  end

  defp end_run(user, pages, total, failed) do
    images_failed? = pages["images_failed"] == true

    Work.in_locale(user, fn ->
      message = result_message(pages["images"] || 0, images_failed?, total, failed)

      if images_failed? or failed > 0,
        do: Work.fail(user, @work_key, message),
        else: Work.finish(user, @work_key, message)
    end)

    :ok
  end

  @doc false
  # "65 images recreated, 14 pages updated", in the current locale
  @spec result_message(non_neg_integer(), boolean(), non_neg_integer(), non_neg_integer()) :: String.t()
  def result_message(images, images_failed?, pages, failed_pages) do
    images =
      cond do
        images_failed? -> gettext("Some images could not be recreated")
        images == 0 -> gettext("No images to recreate")
        true -> ngettext("%{count} image recreated", "%{count} images recreated", images)
      end

    cond do
      pages == 0 ->
        images

      failed_pages > 0 ->
        gettext("%{images}, %{pages}",
          images: images,
          pages: ngettext("%{count} page could not be updated", "%{count} pages could not be updated", failed_pages)
        )

      true ->
        gettext("%{images}, %{pages}",
          images: images,
          pages: ngettext("%{count} page updated", "%{count} pages updated", pages)
        )
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
  it ends, so the job that takes its place carries the run's mark and
  reports none: the image is counted once, when the replaced job ends. The
  work can then end before the new job is done, and does not hear of it
  failing. The run, read from the jobs, goes on until the new job is done.
  """
  @spec carry_over(Ecto.Changeset.t(), [%{state: String.t(), meta: map()}]) :: Ecto.Changeset.t()
  def carry_over(changeset, deleted) do
    case Enum.find(deleted, &(&1.state in @unfinished_states and Map.has_key?(&1.meta || %{}, @meta_key))) do
      nil ->
        changeset

      %{state: state, meta: replaced} ->
        keys = if state == "executing", do: [@meta_key], else: [@meta_key, Work.meta_key()]
        meta = Ecto.Changeset.get_field(changeset, :meta) || %{}
        Ecto.Changeset.put_change(changeset, :meta, Map.merge(meta, Map.take(replaced, keys)))
    end
  end

  @doc """
  No more images. A run with a watcher (`run`, its id) gives it the count,
  `queued`, and its work goes on to the pages (`pages/2`), even with none
  queued: the images it adopted may have pages to render. A run without one
  ends when the last queued image is done, or at once when there were none.
  """
  @spec close(Processing.user(), non_neg_integer(), String.t() | nil) :: :ok
  def close(user, queued, run \\ nil) do
    if is_nil(run) or tell_watcher(run, queued) == 0,
      do: Work.in_locale(user, fn -> Work.close(user, @work_key, done: closed(queued)) end)

    :ok
  end

  defp closed(0), do: gettext("No images to recreate")
  defp closed(queued), do: ngettext("%{count} image recreated", "%{count} images recreated", queued)

  # Returns how many watchers it told: none when the run has none
  defp tell_watcher(run, queued) do
    worker = Oban.Worker.to_string(Worker.ImageMaintenance)
    args = TenantJob.attach(%{"run" => run, "watch" => true})

    query =
      from j in Oban.Job,
        where: j.worker == ^worker and j.state in ^@unfinished_states and fragment("? @> ?", j.args, ^args),
        update: [set: [args: fragment("? || ?", j.args, type(^%{"queued" => queued}, :map))]]

    {count, _} = Brando.Repo.update_all(query, [])
    count
  end

  defp mark(changeset, user, image, run) do
    meta = Ecto.Changeset.get_field(changeset, :meta) || %{}

    changeset
    |> Ecto.Changeset.put_change(:meta, Map.put(meta, @meta_key, run || true))
    |> Work.track(user, @work_key, step: true, item: image.id)
  end
end

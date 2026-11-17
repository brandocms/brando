defmodule Brando.Content.RenderRun do
  @moduledoc false
  # The render and cascade jobs one piece of work queued, and following them
  # to the end, on whichever node runs them (`Brando.Content.Definitions.await_refresh/2`).
  #
  # `track/1` gives the work a run id. Every `EntryRenderer` and `EntryCascade`
  # job queued while it runs carries the id in its meta (`tag/1`), and so does
  # a waiting job the work's render coalesced into (`RenderQueue.coalesce/3`):
  # that one renders for it. A job of the run hands the id on to the jobs it
  # queues (`within/2`): a cascade queues the renders of the entries that list
  # the one saved, and the render of a fragment those of the entries that embed it.
  # A job queued in the run's process by anything else (a revision, a search
  # index update) carries nothing and is not followed.

  import Ecto.Query, only: [from: 2]

  alias Brando.Repo

  @key {__MODULE__, :runs}
  @meta "brando_runs"
  @renderer "Brando.Worker.EntryRenderer"
  @cascade "Brando.Worker.EntryCascade"
  @workers [@renderer, @cascade]
  # A job that has failed an attempt has its error: Oban retries it later, on
  # a node that runs its queue, and the run reports it as failed now rather
  # than wait out the backoff
  @settled ~w(completed discarded cancelled retryable)
  @failed ~w(discarded cancelled retryable)

  @type result :: Brando.Content.Definitions.refresh_result()

  @doc "Runs `fun` as a new run. Returns `{fun's result, run id}`."
  @spec track((-> term)) :: {term, String.t()}
  def track(fun) when is_function(fun, 0) do
    run = Ecto.UUID.generate()
    {with_runs([run], fun), run}
  end

  @doc "Runs `fun` within the runs of `job`, so the jobs it queues belong to them too."
  @spec within(Oban.Job.t(), (-> term)) :: term
  def within(%Oban.Job{meta: %{@meta => runs}}, fun) when is_list(runs) and runs != [], do: with_runs(runs, fun)
  def within(%Oban.Job{}, fun), do: fun.()

  defp with_runs(runs, fun) do
    previous = Process.get(@key)
    Process.put(@key, Enum.uniq((previous || []) ++ runs))

    try do
      fun.()
    after
      if previous, do: Process.put(@key, previous), else: Process.delete(@key)
    end
  end

  @doc "The runs the current process works for."
  @spec current() :: [String.t()]
  def current, do: Process.get(@key) || []

  @doc "Marks a job changeset as one of the current runs'."
  @spec tag(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def tag(changeset) do
    case current() do
      [] ->
        changeset

      runs ->
        meta = Ecto.Changeset.get_field(changeset, :meta) || %{}
        Ecto.Changeset.put_change(changeset, :meta, Map.update(meta, @meta, runs, &Enum.uniq(&1 ++ runs)))
    end
  end

  @doc """
  Adds the current runs to the meta of the jobs `query` updates, as the
  update's `meta` (a query from `Oban.Job` as `j`).
  """
  @spec tag_update(Ecto.Query.t(), keyword) :: Ecto.Query.t()
  def tag_update(query, set) do
    query = from(j in query, update: [set: ^set])

    case current() do
      [] ->
        query

      runs ->
        from(j in query,
          update: [
            set: [
              meta:
                fragment(
                  "jsonb_set(?, ?, COALESCE(? -> ?, '[]'::jsonb) || to_jsonb(?::text[]))",
                  j.meta,
                  ^[@meta],
                  j.meta,
                  ^@meta,
                  ^runs
                )
            ]
          ]
        )
    end
  end

  @doc "Where the run's jobs are now: `await/2` once, without waiting."
  @spec status(String.t()) :: result
  def status(run), do: run |> poll(%{}) |> summarize(false)

  @doc """
  Follows the run's jobs until each has completed or failed, or `:timeout`
  milliseconds (default 10 minutes) have passed. Polls the jobs table every
  `:interval` milliseconds (500), so it sees jobs any node runs, and calls
  `:on_progress` with `%{done: n, total: n, failed: n}` when that changes.
  """
  @spec await(String.t(), keyword) :: result
  def await(run, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, :timer.minutes(10))
    interval = Keyword.get(opts, :interval, 500)
    on_progress = Keyword.get(opts, :on_progress, fn _ -> :ok end)
    deadline = System.monotonic_time(:millisecond) + timeout
    follow(run, %{}, nil, deadline, interval, on_progress)
  end

  defp follow(run, seen, last, deadline, interval, on_progress) do
    seen = poll(run, seen)
    progress = progress(seen)
    if progress != last, do: on_progress.(progress)
    left = deadline - System.monotonic_time(:millisecond)

    cond do
      Enum.all?(Map.values(seen), &(&1.state in @settled)) ->
        summarize(seen, false)

      left <= 0 ->
        summarize(seen, true)

      true ->
        Process.sleep(min(interval, left))
        follow(run, seen, progress, deadline, interval, on_progress)
    end
  end

  # Every job of the run seen so far, by id. The Pruner deletes finished
  # jobs a few minutes after they finished (completed ones after they were
  # scheduled), and no others: a job that has gone keeps the outcome it was
  # last seen with, and one last seen unfinished counts as completed.
  defp poll(run, seen) do
    query =
      from(j in Oban.Job,
        where: j.worker in ^@workers,
        where: fragment("? @> ?", j.meta, type(^%{@meta => [run]}, :map)),
        select: %{id: j.id, worker: j.worker, state: j.state, args: j.args, errors: j.errors}
      )

    found = Map.new(Repo.all(query, prefix: "public"), &{&1.id, entry(&1)})

    gone =
      for {id, job} <- seen, not Map.has_key?(found, id), into: %{} do
        if job.state in @settled, do: {id, job}, else: {id, %{job | state: "completed"}}
      end

    Map.merge(gone, found)
  end

  defp entry(%{worker: worker, state: state, args: args, errors: errors}) do
    %{
      worker: if(worker == @cascade, do: :cascade, else: :render),
      schema: schema(args["schema"]),
      entry_id: args["entry_id"],
      tenant_prefix: args["tenant_prefix"],
      state: state,
      error: if(state in @failed, do: last_error(errors))
    }
  end

  # Queued with the module, an atom, or its name
  defp schema("Elixir." <> name), do: name
  defp schema(name), do: name

  defp last_error([]), do: nil
  defp last_error(errors), do: errors |> List.last() |> Map.get("error")

  defp progress(seen) do
    renders = renders(seen)
    failed = Enum.count(renders, fn {_entry, jobs} -> Enum.any?(jobs, &(&1.state in @failed)) end)
    done = Enum.count(renders, fn {_entry, jobs} -> Enum.all?(jobs, &(&1.state in @settled)) end)
    %{done: done, total: map_size(renders), failed: failed}
  end

  # The run's renders by entry: an entry may have more than one, when one
  # was queued while another of it was running
  defp renders(seen) do
    seen |> Map.values() |> Enum.filter(&(&1.worker == :render)) |> Enum.group_by(&key/1)
  end

  defp key(job), do: {job.tenant_prefix, job.schema, job.entry_id}

  defp summarize(seen, timed_out) do
    jobs = seen |> Enum.sort_by(&elem(&1, 0)) |> Enum.map(&elem(&1, 1))
    failed = jobs |> Enum.filter(&(&1.state in @failed)) |> Enum.uniq_by(&{&1.worker, key(&1)})
    failed_keys = MapSet.new(failed, &{&1.worker, key(&1)})

    pending =
      jobs
      |> Enum.reject(&(&1.state in @settled or MapSet.member?(failed_keys, {&1.worker, key(&1)})))
      |> Enum.uniq_by(&{&1.worker, key(&1)})

    rendered =
      Enum.count(renders(seen), fn {_entry, jobs} -> Enum.all?(jobs, &(&1.state == "completed")) end)

    %{rendered: rendered, failed: failed, pending: pending, timed_out: timed_out}
  end
end

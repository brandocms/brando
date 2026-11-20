defmodule Brando.Content.RenderQueue do
  @moduledoc """
  Enqueues entry-rendering jobs at the content pipeline's asynchronous boundary.

  The worker is resolved at runtime so producers do not depend on the worker's
  block-rendering implementation.

  ## Two lanes

  A save's render of its own entry (`enqueue/2`) runs at Oban priority 0.
  The renders bulk work queues for the entries a change reaches
  (`enqueue_map/2`, `enqueue_many/3`) run at a lower one, so an editor's
  render, uploads and the other jobs in the `default` queue go ahead of
  them. The queue and its limit stay as the site configured them.

  Whatever lane it came by, an entry has at most one render waiting: a
  render queued for it while one waits merges into that one, whatever its
  age, and an interactive render that merges into a bulk one moves it to the
  front.

  ## Held renders

  Work that runs outside the `default` queue, or outside Oban, finishes
  alongside the renders it queues, so the lanes alone would render an entry
  it reaches once per step. It holds them instead:
  `enqueue_map(entries, hold: key)` queues the renders to run after a
  maximum hold (15 minutes), and the renders queued for those entries
  meanwhile merge into them. `release/1` makes them run now: at the end of
  the work, or once per batch of a long one. A run that dies without
  releasing still has its entries rendered when the hold runs out.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Cache.Freshness
  alias Brando.Content.RenderRun
  alias BrandoAdmin.Work

  @entry_renderer Module.concat(["Brando", "Worker", "EntryRenderer"])
  @worker_name "Brando.Worker.EntryRenderer"
  # The unique states of the render and cascade workers: a job that has not
  # started reads the write that queues another for its entry
  @waiting ~w(available scheduled)
  # What identifies a render's entry, as the renderer's `unique` keys do
  @entry_keys ~w(tenant_prefix schema entry_id)
  @bulk_priority 5
  @hold "brando_hold"
  @max_hold :timer.minutes(15)
  @insert_chunk 1_000

  @type entries :: %{optional(module() | String.t()) => [integer()]}

  @doc "The Oban priority of the renders bulk work queues."
  @spec bulk_priority() :: pos_integer()
  def bulk_priority, do: @bulk_priority

  @doc "How long a held render waits for `release/1`, in milliseconds."
  @spec max_hold() :: pos_integer()
  def max_hold, do: @max_hold

  @doc """
  Enqueues a render of every entry in a schema-to-entry-ids map, in the bulk
  lane, in one insert.

  An entry listed twice is queued once, and one with a render waiting
  (`available` or `scheduled`) merges into it: the waiting job takes this
  one's freshness tokens and runs, so it renders for both. The others are
  inserted together.

  Returns `{:ok, job}` for each entry, the job it merged into or the one it
  inserted.

  Options:

    * `:hold` — a key: the renders inserted wait for `release/1` with it, or
      the maximum hold, and a held render this one merges into waits for
      either key (see "Held renders")
    * `:work` — `{user, key}` or `{user, key, opts}`: each render counts as
      a step of `BrandoAdmin.Work` work under `key`, which starts with
      `total:` the number of entries, or adds them to its count if it
      runs. `opts` are `start/4`'s, with its message as `:message`. A
      waiting render that already counts for other work counts at once.
  """
  @spec enqueue_map(entries(), keyword()) :: [{:ok, Oban.Job.t()}]
  def enqueue_map(entries_by_schema, opts \\ []) do
    entries_by_schema
    |> Enum.flat_map(fn {schema, entry_ids} -> Enum.map(entry_ids, &%{schema: schema, entry_id: &1}) end)
    |> enqueue_bulk(opts)
  end

  @doc """
  Enqueues all `entry_ids` for `schema`, as `enqueue_map/2` does.
  """
  @spec enqueue_many(module() | String.t(), [integer()], keyword()) :: [{:ok, Oban.Job.t()}]
  def enqueue_many(schema, entry_ids, opts \\ []), do: enqueue_map(%{schema => entry_ids}, opts)

  @doc """
  Makes the renders held with `key` (`enqueue_map/2`) run now. Returns how
  many it released.
  """
  @spec release(String.t()) :: non_neg_integer()
  def release(key) when is_binary(key) do
    query =
      from(j in Oban.Job,
        where: j.worker == @worker_name and j.state == "scheduled",
        where: fragment("? @> ?", j.meta, type(^%{@hold => [key]}, :map))
      )

    {count, _} = Brando.Repo.update_all(query, set: [state: "available", scheduled_at: DateTime.utc_now()])
    count
  end

  defp enqueue_bulk(entries, opts) do
    hold = Keyword.get(opts, :hold)
    work = work_option(Keyword.get(opts, :work))
    # This node's tokens, the same for every entry
    tokens = Freshness.attach(%{})

    requests =
      entries
      |> Enum.map(&(&1 |> Map.merge(tokens) |> Brando.Tenant.Job.attach()))
      |> Enum.uniq_by(&entry_key/1)

    if requests == [] do
      []
    else
      start_work(work, length(requests))
      {merged, rest} = merge_waiting(requests, hold, work)
      merged ++ insert(rest, hold, work)
    end
  end

  # One query for the renders of these entries that wait, and one to merge
  # into them. Like `coalesce/4`, each update holds only while the job still
  # waits with the arguments and meta it was read with: one that has started,
  # or that another insert merged into since, gets a render of its own.
  defp merge_waiting(requests, hold, work) do
    by_key = Map.new(requests, &{entry_key(&1), &1})

    updates =
      by_key
      |> Map.keys()
      |> waiting()
      |> Enum.map(fn job ->
        more = Map.fetch!(by_key, entry_key(job.args))
        {job, Freshness.merge(job.args, more), merged_meta(job, hold, work)}
      end)

    updated = update_waiting(updates)
    merged = for {job, args, meta} <- updates, MapSet.member?(updated, job.id), do: %{job | args: args, meta: meta}

    for job <- merged, counts_elsewhere?(job, work) do
      {user, key, opts} = work
      Work.advance(user, key, :ok, Keyword.take(opts, [:global]))
    end

    merged_keys = MapSet.new(merged, &entry_key(&1.args))
    {Enum.map(merged, &{:ok, &1}), Enum.reject(requests, &MapSet.member?(merged_keys, entry_key(&1)))}
  end

  # The first waiting render of each entry
  defp waiting(keys) do
    query =
      from(j in Oban.Job,
        where: j.worker == @worker_name and j.state in @waiting,
        where: fragment("? @> ANY(?)", j.args, type(^keys, {:array, :map})),
        order_by: j.id
      )

    keys = MapSet.new(keys)

    query
    |> Brando.Repo.all()
    |> Enum.filter(&MapSet.member?(keys, entry_key(&1.args)))
    |> Enum.uniq_by(&entry_key(&1.args))
  end

  defp update_waiting([]), do: MapSet.new()

  defp update_waiting(updates) do
    ids = Enum.map(updates, fn {job, _, _} -> job.id end)
    read_args = Enum.map(updates, fn {job, _, _} -> job.args end)
    read_meta = Enum.map(updates, fn {job, _, _} -> job.meta end)
    args = Enum.map(updates, fn {_, args, _} -> args end)
    meta = Enum.map(updates, fn {_, _, meta} -> meta end)

    query =
      from(j in Oban.Job,
        join:
          v in fragment(
            "SELECT * FROM unnest(?::bigint[], ?::jsonb[], ?::jsonb[], ?::jsonb[], ?::jsonb[]) AS v(id, read_args, read_meta, args, meta)",
            ^ids,
            ^read_args,
            ^read_meta,
            ^args,
            ^meta
          ),
        on: j.id == v.id,
        where: j.state in @waiting and j.args == v.read_args and j.meta == v.read_meta,
        update: [set: [args: v.args, meta: v.meta]],
        select: j.id
      )

    {_count, updated} = Brando.Repo.update_all(query, [])
    MapSet.new(updated)
  end

  # The runs this work belongs to, the hold of this one if the job is held
  # too, and the work's step if it counts for none
  defp merged_meta(job, hold, work) do
    meta = RenderRun.tag_meta(job.meta)

    meta =
      if hold && held?(job),
        do: Map.update!(meta, @hold, &Enum.uniq(&1 ++ [hold])),
        else: meta

    case work do
      {user, key, opts} when not is_map_key(meta, "brando_work") -> track_meta(meta, user, key, opts)
      _ -> meta
    end
  end

  defp held?(%{state: "scheduled", meta: %{@hold => holds}}) when is_list(holds), do: true
  defp held?(_job), do: false

  defp counts_elsewhere?(_job, nil), do: false

  defp counts_elsewhere?(%{meta: %{"brando_work" => tracked}}, {user, key, _opts}),
    do: not (tracked["user_id"] == Work.user_id(user) and tracked["key"] == key)

  defp insert([], _hold, _work), do: []

  defp insert(requests, hold, work) do
    worker = @entry_renderer

    requests
    |> Enum.map(fn args ->
      args
      |> worker.new(bulk_options(hold))
      |> Ecto.Changeset.delete_change(:unique)
      |> RenderRun.tag()
      |> track(work)
    end)
    # `Oban.insert_all/1` is one statement, and Postgres takes at most 65,535
    # parameters in one: about 6,000 jobs
    |> Enum.chunk_every(@insert_chunk)
    |> Enum.flat_map(&Oban.insert_all/1)
    |> Enum.map(&{:ok, &1})
  end

  defp bulk_options(nil), do: [tags: [:render_entry], priority: @bulk_priority]

  defp bulk_options(hold) do
    until = DateTime.add(DateTime.utc_now(), @max_hold, :millisecond)
    bulk_options(nil) ++ [scheduled_at: until, meta: %{@hold => [hold]}]
  end

  defp work_option(nil), do: nil
  defp work_option({user, key}), do: work_option({user, key, []})

  defp work_option({user, key, opts}) do
    if Work.user_id(user), do: {user, key, opts}
  end

  defp start_work(nil, _total), do: :ok

  defp start_work({user, key, opts}, total) do
    {message, opts} = Keyword.pop(opts, :message)
    Work.start(user, key, message, Keyword.put(opts, :total, total))
  end

  defp track(changeset, nil), do: changeset

  defp track(changeset, {user, key, opts}),
    do: Work.track(changeset, user, key, [step: true] ++ Keyword.take(opts, [:global, :timeout, :toast]))

  defp track_meta(meta, user, key, opts) do
    %Oban.Job{meta: meta}
    |> Ecto.Changeset.change()
    |> track({user, key, opts})
    |> Ecto.Changeset.get_field(:meta)
  end

  # As the jobs table holds it
  defp entry_key(args) do
    args
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> Map.take(@entry_keys)
    |> JSON.encode!()
    |> JSON.decode!()
  end

  @doc """
  Enqueues one entry-rendering job. It carries what this node's render
  inputs have caught up with, so a node that has not caught up yet does
  before it renders (`Brando.Cache.ensure_fresh/1`).

  With `refresh: :all` it carries instead that every input is to be
  refreshed, whatever the node that runs it has heard: for a render queued
  because this node rendered from inputs it had not caught up with
  (`Brando.Content.Blocks.store_fenced/3`).

  A render of the entry queued and not started yet takes this one's tokens
  instead (`coalesce/4`), however long it has waited, and runs in this
  one's lane: a bulk render runs next, and a held one now. One that has
  started may have read the entry and its inputs before the write that
  queues this one, so this one runs after it.
  """
  @spec enqueue(map(), keyword()) :: term()
  def enqueue(args, opts \\ []) do
    worker = @entry_renderer
    attach = if Keyword.get(opts, :refresh) == :all, do: &Freshness.attach_any/1, else: &Freshness.attach/1

    changeset =
      args
      |> attach.()
      |> Brando.Tenant.Job.attach()
      |> worker.new(tags: [:render_entry])
      |> RenderRun.tag()

    changeset
    |> Oban.insert()
    |> coalesce(changeset, &Freshness.merge/2, &promote/1)
  end

  # An interactive render never waits for a bulk or held one
  defp promote(query) do
    now = DateTime.utc_now()

    from(j in query,
      update: [
        set: [
          priority: 0,
          state: fragment("CASE WHEN ?->? IS NOT NULL THEN 'available' ELSE ? END", j.meta, @hold, j.state),
          scheduled_at:
            fragment(
              "CASE WHEN ?->? IS NOT NULL AND ? = 'scheduled' THEN ? ELSE ? END",
              j.meta,
              @hold,
              j.state,
              type(^now, :utc_datetime_usec),
              j.scheduled_at
            )
        ]
      ]
    )
  end

  @doc false
  # What `Oban.insert/1` returned for `changeset`, with a conflict resolved:
  # the job it found waiting takes the arguments `merge` makes from its own
  # and the changeset's, or, when there is none to take them, the changeset
  # is inserted as it is.
  #
  # The update is conditional: the job may have started since Oban found it,
  # or another insert may have changed its arguments. Inside a transaction
  # it also holds the job until the transaction commits, so the job cannot
  # start before the write that queued this. A conflict without a job is a
  # unique insert of another transaction holding the lock: that transaction's
  # job may run before this write commits.
  #
  # `update` adds to the update of the job found what else it should change.
  @spec coalesce(
          {:ok, Oban.Job.t()} | term(),
          Ecto.Changeset.t(),
          (map(), map() -> map()),
          (Ecto.Query.t() -> Ecto.Query.t())
        ) :: term()
  def coalesce(result, changeset, merge, update \\ & &1)

  def coalesce({:ok, %Oban.Job{conflict?: true, id: nil}}, changeset, _merge, _update), do: insert_anyway(changeset)

  def coalesce({:ok, %Oban.Job{conflict?: true} = job}, changeset, merge, update) do
    args = merge.(job.args, Ecto.Changeset.get_field(changeset, :args))

    # It renders for the runs this one would have too (`RenderRun`)
    query =
      from(j in Oban.Job, where: j.id == ^job.id and j.state in @waiting and j.args == type(^job.args, :map))
      |> RenderRun.tag_update(args: args)
      |> update.()

    case Brando.Repo.update_all(query, []) do
      {1, _} -> {:ok, %{job | args: args}}
      {0, _} -> insert_anyway(changeset)
    end
  end

  def coalesce(result, _changeset, _merge, _update), do: result

  # A second render runs at worst, and one more read
  defp insert_anyway(changeset), do: changeset |> Ecto.Changeset.delete_change(:unique) |> Oban.insert()
end

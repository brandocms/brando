defmodule Brando.Content.Definitions.Release.Verify do
  @moduledoc """
  Verify: a dry run of a release's module definitions. Each entry that uses
  a module the release changes is rendered with the release's definitions
  (`Brando.Content.Definitions.Release.Proposed`) and with the stored ones,
  and nothing is written: no entry, block, module or job.

  Each entry gets a verdict:

    * `:changed` - it renders, and at least one block's HTML differs
    * `:same` - the output is unchanged
    * `:failed` - a block fails to render with the release's definitions

  `start/3` runs it in the background, one run per environment at a time,
  cancellable with `cancel/1`, and announces its progress on `topic/0` as
  `{:release_verify, prefix, run}`. A run of the same plan keeps what the run
  before it found for entries it doesn't render, so verifying one
  definition after all of them adds to the results. `blocks/3` renders one
  entry's blocks both ways for a per-block diff.

  Each block is rendered as a stored render is (`Brando.Villain.parse_checked/3`),
  with the release's modules in place of the stored ones
  (`Brando.Villain.with_modules/2`): a template that fails to parse or raises
  fails its block, as it would keep the entry's stored HTML.

  The runs are kept on the node that ran them, until the next one.
  """

  alias Brando.Content.Definitions.Release.{Entries, Proposed}
  alias Brando.Tenant
  alias Brando.Villain
  alias Brando.Villain.RenderFailure

  @table __MODULE__
  @supervisor Brando.Content.Definitions.Release.TaskSupervisor

  @type verdict :: :changed | :same | :failed
  @type failure :: %{index: non_neg_integer(), uid: String.t(), module: String.t() | nil, message: String.t()}
  @type result :: %{verdict: verdict(), changed: non_neg_integer(), failures: [failure()]}
  @type run :: %{
          id: String.t(),
          prefix: String.t() | nil,
          status: :running | :done | :cancelled,
          fingerprint: String.t(),
          total: non_neg_integer(),
          done: non_neg_integer(),
          results: %{{module(), integer()} => result()},
          keys: MapSet.t(),
          started_at: DateTime.t(),
          finished_at: DateTime.t() | nil,
          pid: pid() | nil
        }

  @doc "The PubSub topic that hears `{:release_verify, prefix, run}` as a run goes on."
  def topic, do: "brando:release_verify"

  @doc "Its child spec, for `Brando.Supervisor`."
  def child_spec(_), do: Task.Supervisor.child_spec(name: @supervisor)

  @doc """
  Starts a dry run of `report` (`Brando.Content.Definitions.Release.plan/1`)
  for `entries` (`Brando.Content.Definitions.Release.Entries.list/1`), in the
  current environment, cancelling one already running there. `conflicts:`
  as `Proposed.build/2` takes it. Returns `{:ok, run}`.
  """
  @spec start(map(), [Entries.entry()], keyword()) :: {:ok, run()}
  def start(report, entries, opts \\ []) do
    prefix = Tenant.current_prefix()
    previous = cancel(prefix)
    keys = MapSet.new(entries, & &1.key)
    fingerprint = fingerprint(report, opts)

    # What an earlier run of the same plan found for other entries stays
    carried =
      case previous do
        %{fingerprint: ^fingerprint, results: results} ->
          Map.reject(results, fn {key, _} -> MapSet.member?(keys, key) end)

        _ ->
          %{}
      end

    run = %{
      id: Ecto.UUID.generate(),
      prefix: prefix,
      status: :running,
      fingerprint: fingerprint,
      total: length(entries),
      done: 0,
      results: carried,
      keys: keys,
      started_at: DateTime.utc_now(),
      finished_at: nil,
      pid: nil
    }

    put(run)

    {:ok, pid} =
      Task.Supervisor.start_child(@supervisor, fn ->
        Tenant.with_prefix(prefix, fn -> work(run, report, entries, opts) end)
      end)

    {:ok, update(prefix, run.id, &%{&1 | pid: pid}) || %{run | pid: pid}}
  end

  @doc "Stops the run in `prefix` (the current environment by default), keeping what it found."
  def cancel(prefix \\ Tenant.current_prefix()) do
    case get(prefix) do
      %{status: :running, pid: pid} = run ->
        if pid, do: Task.Supervisor.terminate_child(@supervisor, pid)
        run = %{run | status: :cancelled, finished_at: DateTime.utc_now(), pid: nil}
        put(run)
        broadcast(run)
        run

      run ->
        run
    end
  end

  @doc "The latest run in `prefix` (the current environment by default), or nil."
  @spec get(String.t() | nil) :: run() | nil
  def get(prefix \\ Tenant.current_prefix()) do
    case :ets.lookup(@table, prefix || :public) do
      [{_, run}] -> run
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  @doc "Forgets the run in `prefix`."
  def clear(prefix \\ Tenant.current_prefix()) do
    cancel(prefix)
    if :ets.whereis(@table) != :undefined, do: :ets.delete(@table, prefix || :public)
    :ok
  end

  @doc """
  What a run's results hold for: the plan, and the conflicts it proposes the
  release's version of (`conflicts:`, as `Proposed.build/2` takes it).
  """
  def fingerprint(report, opts \\ []) do
    conflicts = opts |> Keyword.get(:conflicts, []) |> Enum.sort() |> Enum.join(",")
    report.plan.fingerprint <> ":" <> conflicts
  end

  defp work(run, report, entries, opts) do
    proposed = Proposed.build(report, Keyword.take(opts, [:conflicts]))
    delay = Keyword.get(opts, :delay, 0)

    Enum.each(entries, fn entry ->
      result = safe_check(entry, proposed)
      if delay > 0, do: Process.sleep(delay)

      if updated = update(run.prefix, run.id, &record(&1, entry.key, result)),
        do: broadcast(updated)
    end)

    if finished = update(run.prefix, run.id, &%{&1 | status: :done, finished_at: DateTime.utc_now(), pid: nil}),
      do: broadcast(finished)
  end

  # Whatever goes wrong with one entry is its verdict, not the end of the run
  defp safe_check(entry, proposed) do
    check(entry.schema, entry.id, proposed)
  rescue
    error ->
      %{verdict: :failed, changed: 0, failures: [%{index: 0, uid: nil, module: nil, message: Exception.message(error)}]}
  end

  defp record(%{status: :running} = run, key, result),
    do: %{run | results: Map.put(run.results, key, result), done: run.done + 1}

  defp record(run, _key, _result), do: run

  @doc """
  Renders the entry `id` of `schema` with the stored definitions and with
  `proposed`, and returns its verdict (`t:result/0`). Writes nothing.
  """
  @spec check(module(), integer(), Proposed.t()) :: result()
  def check(schema, id, proposed) do
    case blocks(schema, id, proposed) do
      {:ok, blocks} ->
        failures = for %{state: :failed} = block <- blocks, do: Map.take(block, [:index, :uid, :module, :message])
        changed = Enum.count(blocks, &(&1.state == :changed))

        verdict =
          cond do
            failures != [] -> :failed
            changed > 0 -> :changed
            true -> :same
          end

        %{verdict: verdict, changed: changed, failures: failures}

      {:error, message} ->
        %{verdict: :failed, changed: 0, failures: [%{index: 0, uid: nil, module: nil, message: message}]}
    end
  end

  @doc """
  The root blocks of the entry `id` of `schema`, in every block field, each
  rendered with the stored definitions (`before`) and the proposed ones
  (`after`) when it uses a module the release changes: `state` is
  `:changed`, `:same`, `:failed` (with `message`) or `:untouched` (it uses
  no such module, so it isn't rendered). Writes nothing.
  """
  @spec blocks(module(), integer(), Proposed.t()) :: {:ok, [map()]} | {:error, String.t()}
  def blocks(schema, id, proposed) do
    case Brando.Blueprint.EntryQuery.get(schema, id) do
      {:ok, entry} -> {:ok, entry_blocks(schema, entry, proposed)}
      {:error, _} -> {:error, "the entry is gone"}
    end
  end

  defp entry_blocks(schema, entry, proposed) do
    names = module_names(proposed)

    schema.__blocks_fields__()
    |> Enum.flat_map(fn field ->
      entry
      |> Map.get(:"entry_#{field.name}")
      |> List.wrap()
      |> Enum.map(& &1.block)
      |> Enum.reject(&(is_nil(&1) or Map.get(&1, :marked_as_deleted) == true))
      |> Enum.map(&{field.name, &1})
    end)
    |> Enum.with_index(1)
    |> Enum.map(fn {{field, block}, index} -> block_result(field, block, index, entry, proposed, names) end)
  end

  defp block_result(field, block, index, entry, proposed, names) do
    base = %{
      index: index,
      field: field,
      uid: block.uid,
      module: names[block.module_id] || module_name(block),
      before: nil,
      after: nil,
      message: nil
    }

    if uses?(block, proposed.changed),
      do: compare(base, render_stored(block, entry), render_proposed(block, entry, proposed), names),
      else: Map.put(base, :state, :untouched)
  end

  # A block that fails with the stored definitions and renders with the
  # release's is a change: the release fixes it
  defp compare(base, {:ok, before}, {:ok, html}, _names) do
    state = if normalize(html) == normalize(before), do: :same, else: :changed
    Map.put(%{base | before: before, after: html}, :state, state)
  end

  defp compare(base, {:error, _}, {:ok, html}, _names), do: Map.put(%{base | before: "", after: html}, :state, :changed)

  defp compare(base, before, {:error, failure}, names) do
    base = %{
      base
      | before: elem_ok(before),
        message: failure_message(failure),
        module: module_label(failure, base.module, names)
    }

    Map.put(base, :state, :failed)
  end

  defp failure_message(%RenderFailure{} = failure), do: RenderFailure.describe(failure)
  defp failure_message(_), do: "the block failed to render"

  # The failing block may be a child of the root: its module is the one named
  defp module_label(%RenderFailure{module_id: id, module_name: name}, root, names) when not is_nil(id),
    do: names[id] || name || root

  defp module_label(_failure, root, _names), do: root

  defp elem_ok({:ok, html}), do: html
  defp elem_ok(_), do: nil

  # Rendered as a stored render is (`Brando.Villain.parse_checked/3`): a
  # template that fails to parse or raises is a failure of its block, named
  # by the innermost block that failed, never output with an error in it
  defp render_stored(block, entry), do: checked(block, entry)

  defp render_proposed(block, entry, proposed) do
    synced = Proposed.sync_block(block, proposed)
    Villain.with_modules(proposed.modules, fn -> checked(synced, entry) end)
  end

  defp checked(block, entry) do
    case Villain.parse_checked([%{block: block}], entry) do
      {:ok, html} -> {:ok, html}
      {:error, [failure | _]} -> {:error, failure}
      {:error, []} -> {:error, nil}
    end
  end

  defp uses?(%{module_id: id} = block, changed) when not is_nil(id) do
    Map.has_key?(changed, id) or children_use?(block, changed)
  end

  defp uses?(block, changed), do: children_use?(block, changed)

  defp children_use?(block, changed) do
    case Map.get(block, :children) do
      children when is_list(children) -> Enum.any?(children, &uses?(&1, changed))
      _ -> false
    end
  end

  # Only around the block: whitespace between tags can show on the page
  defp normalize(nil), do: ""
  defp normalize(html), do: String.trim(html)

  defp module_names(%{modules: modules}), do: Map.new(modules, &{&1.id, label(&1)})

  defp module_name(%{module: %Brando.Content.Module{} = module}), do: label(module)
  defp module_name(_block), do: nil

  @doc "A module's name as the admin shows it: namespace › name."
  def label(module) do
    language = to_string(Brando.config(:default_admin_language) || "en")
    namespace = text(module.namespace, language)
    name = text(module.name, language)
    if namespace in [nil, ""], do: name, else: "#{namespace} › #{name}"
  end

  defp text(%{} = map, language),
    do: map[language] || map[String.to_atom(language)] || map |> Map.values() |> List.first()

  defp text(value, _language), do: value

  ## Storage

  @doc false
  def init_table do
    if :ets.whereis(@table) == :undefined,
      do: :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])

    :ok
  rescue
    ArgumentError -> :ok
  end

  defp put(run) do
    init_table()
    :ets.insert(@table, {run.prefix || :public, run})
  end

  # Updates the run `id` in `prefix`, unless another has replaced it
  defp update(prefix, id, fun) do
    case get(prefix) do
      %{id: ^id} = run ->
        run = fun.(run)
        put(run)
        run

      _ ->
        nil
    end
  end

  defp broadcast(run), do: Phoenix.PubSub.broadcast(Brando.pubsub(), topic(), {:release_verify, run.prefix, run})
end

defmodule Brando.Blueprint.Migrations do
  @moduledoc """
  Generates reviewed, reversible Ecto migrations from Blueprint storage schemas.

  Migration generation compares normalized storage snapshots rather than live
  DSL structs. Unsupported table and primary-key changes fail explicitly and
  must be handled by a hand-written migration.
  """

  alias Brando.Blueprint.Migrations.{Diff, Plan, Renderer, Schema}
  alias Brando.Blueprint.Snapshot
  alias Brando.Exception.BlueprintError

  @default_opts [
    migration_path: "priv/repo/migrations",
    snapshot_path: "priv/blueprints/snapshots"
  ]

  @doc """
  Generates the next migration and stores its Blueprint snapshot.

  Returns `{:ok, metadata}` for a generated migration and `{:noop, metadata}`
  when the storage schema has not changed. Migration and snapshot creation are
  serialized per Blueprint and use atomic file replacement.
  """
  @spec create_migration(module(), keyword()) :: {:ok | :noop, map()}
  def create_migration(module, opts \\ @default_opts) do
    opts = Keyword.merge(@default_opts, opts)
    with_storage_lock(module, opts, fn -> module |> plan(opts) |> commit_prepared() end)
  end

  @doc """
  Stores the current Blueprint schema as the next snapshot without generating a migration.

  This is an explicit recovery tool for a storage change already implemented by a
  reviewed hand-written migration. It must only be run after the database migration
  has been created and tested.
  """
  @spec rebaseline_snapshot(module(), keyword()) :: {:ok, map()}
  def rebaseline_snapshot(module, opts \\ @default_opts) do
    opts = @default_opts |> Keyword.merge(opts) |> Keyword.put(:rebaseline, true)
    with_storage_lock(module, opts, fn -> module |> plan(opts) |> commit_prepared() end)
  end

  @doc """
  Prepares a migration/snapshot change without creating files or directories.

  History validation, storage diffing and rendering use the same rules as
  `create_migration/2`. The returned plan is valid only while both the compiled
  schema and the migration/snapshot history remain unchanged.
  """
  @spec plan(module(), keyword()) :: Plan.t()
  def plan(module, opts \\ @default_opts) do
    refuse_embedded!(module, "generate a migration for")
    opts = Keyword.merge(@default_opts, opts)
    history = history_digest(module, opts)
    previous = Snapshot.get_latest_snapshot(module, opts)
    schema = Schema.build(module)
    prepared = prepare(module, previous, schema, opts)
    if history != history_digest(module, opts), do: stale_plan!()
    struct!(Plan, Map.merge(prepared, %{module: module, options: opts, history_digest: history, schema: schema}))
  end

  @doc """
  Commits exactly the reviewed migration/snapshot pair after checking for changes.

  A stale plan raises before writing. Migration creation is rolled back if the
  paired snapshot cannot be persisted. The migration directory and Blueprint
  snapshot locks are the same locks used by immediate generation.
  """
  @spec commit_plan(Plan.t()) :: {:ok | :noop, map()}
  def commit_plan(%Plan{} = plan) do
    with_storage_lock(plan.module, plan.options, fn -> commit_prepared(plan) end)
  end

  @doc """
  Prepares storage plans for several Blueprints, to be reviewed and committed together.

  Each entry is `{module, opts}` with the options `plan/2` takes. A Blueprint is
  planned after the Blueprints whose tables it references, otherwise in
  alphabetical order, and each planned migration gets a version above the one
  before it, so the batch applies in that order. Commit the result with
  `commit_plans/1`.
  """
  @spec plan_all([{module(), keyword()}]) :: [Plan.t()]
  def plan_all(entries) do
    entries = Enum.map(entries, fn {module, opts} -> {module, Keyword.merge(@default_opts, opts)} end)
    ensure_distinct_storage!(entries)

    entries
    |> order_by_references()
    |> Enum.map_reduce(nil, fn {module, opts}, previous ->
      version = batch_migration_version(previous, opts)
      plan = plan(module, Keyword.put(opts, :planned_migration_version, version))
      {plan, if(plan.migration_source, do: version, else: previous)}
    end)
    |> elem(0)
  end

  @doc """
  Commits reviewed plans together, or none of them.

  Every plan is checked for changes under the locks of all its migration
  directories and snapshots before anything is written. If a write fails, the
  files already written by the batch are removed or restored.
  """
  @spec commit_plans([Plan.t()]) :: [{:ok | :noop, map()}]
  def commit_plans(plans) do
    ensure_distinct_storage!(Enum.map(plans, &{&1.module, &1.options}))

    with_storage_locks(plans, fn ->
      Enum.each(plans, &ensure_fresh!/1)
      persist_all(plans)
      Enum.map(plans, &{&1.result, &1.metadata})
    end)
  end

  @doc "Fingerprints the reviewed source and history, excluding the snapshot's informational creation time."
  @spec plan_digest(Plan.t()) :: String.t()
  def plan_digest(%Plan{} = plan) do
    snapshot = if plan.snapshot, do: %{plan.snapshot | updated_at: nil}

    options =
      plan.options
      |> Keyword.delete(:planned_migration_version)
      |> Keyword.put(:rebaseline, plan.options[:rebaseline] || false)
      |> Enum.sort()

    %{plan | snapshot: snapshot, options: options}
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @doc """
  Compares two snapshots using the normalized migration schema.
  """
  @spec diff_against(Snapshot.t(), Snapshot.t() | nil) :: {:ok, Diff.t()} | {:error, term()}
  def diff_against(%Snapshot{schema: current_schema}, nil) do
    Diff.compare(current_schema, nil)
  end

  def diff_against(%Snapshot{schema: current_schema}, %Snapshot{schema: previous_schema}) do
    Diff.compare(current_schema, previous_schema)
  end

  # An embedded Blueprint is stored inside its parent entry's column and owns no
  # table, so there is no storage to diff. Without this the generator read it as
  # a brand-new table and proposed a CREATE TABLE that could never be applied.
  defp refuse_embedded!(module, action) do
    if Brando.Blueprint.embedded?(module) do
      raise BlueprintError, """
      Cannot #{action} #{inspect(module)}: it declares `data_layer :embedded`.

      Embedded Blueprints have no table of their own — their storage belongs to
      the Blueprint that embeds them. Generate that Blueprint's migration instead.
      """
    end
  end

  defp prepare(module, previous, schema, opts) do
    if opts[:rebaseline] do
      version = snapshot_version(previous) + 1
      snapshot = %{Snapshot.build_snapshot(module, version) | rebaseline?: true}
      %{result: :ok, snapshot: snapshot, metadata: snapshot_metadata(module, snapshot, opts)}
    else
      ensure_consistent_history!(module, previous, migration_files(module, opts))
      prepare_diff(module, previous, schema, opts)
    end
  end

  defp prepare_diff(module, previous, schema, opts) do
    case Diff.compare(schema, snapshot_schema(previous)) do
      {:ok, diff} ->
        if Diff.empty?(diff),
          do: prepare_noop(module, previous, schema),
          else: prepare_migration(module, diff, schema, previous, opts)

      {:error, reason} ->
        raise_unsupported_change!(module, reason)
    end
  end

  defp prepare_migration(module, diff, schema, previous, opts) do
    sequence = get_sequence(module, opts)
    snapshot = Snapshot.build_snapshot(module, snapshot_version(previous) + 1)
    contents = module |> Renderer.render(sequence, diff, schema, snapshot_schema(previous)) |> format_code()

    metadata =
      snapshot_metadata(module, snapshot, opts)
      |> Map.merge(%{
        migration: build_migration_filename(module, sequence, opts),
        sequence: sequence,
        destructive_operations: Diff.destructive_operations(diff),
        created_tables: Diff.created_tables(diff, schema),
        added_columns: Diff.added_columns(diff, schema)
      })

    %{result: :ok, migration_source: contents, snapshot: snapshot, metadata: metadata}
  end

  defp prepare_noop(module, previous, schema) do
    snapshot =
      case previous do
        %Snapshot{migrated_from_format: format} = previous when format not in [nil, false] ->
          %Snapshot{
            previous
            | format_version: 3,
              migrated_from_format: nil,
              schema: Schema.persistable(schema),
              updated_at: DateTime.utc_now(),
              attributes: nil,
              assets: nil,
              relations: nil,
              traits: nil
          }

        _ ->
          nil
      end

    %{
      result: :noop,
      snapshot: snapshot,
      metadata: %{
        module: module,
        message: "No storage changes necessary",
        snapshot_version: snapshot_version(previous)
      }
    }
  end

  defp snapshot_metadata(module, snapshot, opts) do
    %{module: module, snapshot: snapshot_filename(module, snapshot.version, opts), snapshot_version: snapshot.version}
  end

  defp snapshot_filename(module, version, opts) do
    Path.join(Snapshot.build_path(module, opts), "#{pad_sequence(version)}.snapshot")
  end

  defp commit_prepared(plan) do
    ensure_fresh!(plan)
    persist_plan(plan)
    {plan.result, plan.metadata}
  end

  defp ensure_fresh!(plan) do
    if history_digest(plan.module, plan.options) != plan.history_digest || Schema.build(plan.module) != plan.schema,
      do: stale_plan!()
  end

  # Writes each plan in turn. When one fails, the files the earlier plans wrote
  # are removed, or restored where a plan replaced a snapshot in place.
  defp persist_all(plans) do
    Enum.reduce(plans, [], fn plan, written ->
      originals = original_files(plan)

      try do
        persist_plan(plan)
        originals ++ written
      rescue
        error ->
          Enum.each(written, &restore_file/1)
          reraise error, __STACKTRACE__
      end
    end)
  end

  defp original_files(plan) do
    migration = if plan.migration_source, do: [plan.metadata.migration], else: []
    snapshot = if plan.snapshot, do: [snapshot_filename(plan.module, plan.snapshot.version, plan.options)], else: []
    Enum.map(migration ++ snapshot, &{&1, File.read(&1)})
  end

  defp restore_file({path, {:ok, contents}}), do: File.write!(path, contents)
  defp restore_file({path, _missing}), do: File.rm(path)

  # Locks are taken in one global order (migration directories, then snapshot
  # directories) so a batch and a single run cannot wait on each other.
  defp with_storage_locks(plans, fun) do
    migration_locks =
      plans
      |> Enum.map(& &1.options)
      |> Enum.uniq_by(&Path.expand(Keyword.fetch!(&1, :migration_path)))
      |> Enum.sort_by(&Path.expand(Keyword.fetch!(&1, :migration_path)))
      |> Enum.map(fn opts -> fn inner -> with_migration_lock(opts, inner) end end)

    snapshot_locks =
      plans
      |> Enum.sort_by(&Path.expand(Snapshot.build_path(&1.module, &1.options)))
      |> Enum.map(fn plan -> fn inner -> Snapshot.with_lock(plan.module, plan.options, inner) end end)

    (migration_locks ++ snapshot_locks)
    |> Enum.reverse()
    |> Enum.reduce(fun, fn lock, inner -> fn -> lock.(inner) end end)
    |> then(& &1.())
  end

  # Two Blueprints sharing a snapshot directory would write the same snapshot
  # version and migration name.
  defp ensure_distinct_storage!(entries) do
    entries
    |> Enum.group_by(fn {module, opts} -> Path.expand(Snapshot.build_path(module, opts)) end, &elem(&1, 0))
    |> Enum.find(fn {_path, modules} -> length(modules) > 1 end)
    |> case do
      nil ->
        :ok

      {path, modules} ->
        raise BlueprintError,
          message:
            "#{Enum.map_join(modules, " and ", &inspect/1)} share the snapshot directory #{path}. Give each Blueprint its own application, domain and schema naming before planning them together."
    end
  end

  # Places each Blueprint after the Blueprints whose tables it references, so a
  # new table exists before a foreign key to it is added. Ties and reference
  # cycles fall back to alphabetical order.
  defp order_by_references(entries) do
    entries = Enum.sort_by(entries, fn {module, _} -> inspect(module) end)
    storage = Map.new(entries, fn {module, _} -> {module, tables_and_references(module)} end)
    owners = for {module, {tables, _}} <- storage, table <- tables, into: %{}, do: {table, module}

    dependencies =
      Map.new(storage, fn {module, {_, references}} ->
        {module, references |> Enum.map(&owners[&1]) |> Enum.reject(&(&1 in [nil, module])) |> MapSet.new()}
      end)

    sort_dependencies(entries, dependencies, [])
  end

  defp sort_dependencies([], _dependencies, sorted), do: Enum.reverse(sorted)

  defp sort_dependencies([first | _] = pending, dependencies, sorted) do
    waiting = MapSet.new(pending, &elem(&1, 0))

    entry =
      Enum.find(pending, first, fn {module, _} -> MapSet.disjoint?(dependencies[module], waiting) end)

    sort_dependencies(List.delete(pending, entry), dependencies, [entry | sorted])
  end

  defp tables_and_references(module) do
    schema = Schema.build(module)
    columns = schema.columns ++ Enum.flat_map(schema.auxiliary_tables, & &1.columns)
    tables = Enum.map([schema.table | Enum.map(schema.auxiliary_tables, & &1.name)], &to_string/1)
    references = for %{reference: %{table: table}} <- columns, do: to_string(table)
    {tables, references}
  end

  defp persist_plan(%Plan{migration_source: nil, snapshot: nil}), do: :ok

  defp persist_plan(%Plan{migration_source: nil} = plan) do
    Snapshot.store_snapshot(plan.snapshot, plan.module, plan.options)
  end

  defp persist_plan(%Plan{} = plan) do
    filename = plan.metadata.migration
    File.mkdir_p!(Path.dirname(filename))
    atomic_write!(filename, plan.migration_source)

    try do
      Snapshot.store_snapshot(plan.snapshot, plan.module, plan.options)
    rescue
      error ->
        File.rm(filename)
        reraise error, __STACKTRACE__
    end
  end

  defp history_digest(module, opts) do
    migrations = opts |> Keyword.fetch!(:migration_path) |> Path.join("*.exs") |> Path.wildcard()
    snapshots = module |> Snapshot.build_path(opts) |> Path.join("*.snapshot") |> Path.wildcard()

    (migrations ++ snapshots)
    |> Enum.sort()
    |> Enum.map(fn path -> {Path.expand(path), :crypto.hash(:sha256, File.read!(path))} end)
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
  end

  defp with_storage_lock(module, opts, fun) do
    with_migration_lock(opts, fn -> Snapshot.with_lock(module, opts, fun) end)
  end

  defp stale_plan! do
    raise BlueprintError,
          "Blueprint schema or migration/snapshot history changed after planning. Generate and review a new plan; no files were written."
  end

  defp snapshot_schema(nil), do: nil
  defp snapshot_schema(%Snapshot{schema: schema}), do: schema

  defp snapshot_version(nil), do: 0
  defp snapshot_version(%Snapshot{version: version}), do: version

  defp get_sequence(module, opts) do
    module
    |> migration_files(opts)
    |> Enum.map(&migration_sequence!/1)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
    |> pad_sequence()
  end

  @doc "Lists a compiled Blueprint's migration history without creating directories or files."
  def migration_files(module, opts \\ []) do
    filename_core = build_filename_core(module)
    migration_path = Keyword.get(opts, :migration_path, @default_opts[:migration_path])
    Path.wildcard(Path.join(migration_path, "*_#{filename_core}_*.exs"))
  end

  defp ensure_consistent_history!(_module, nil, []), do: :ok
  defp ensure_consistent_history!(_module, %Snapshot{}, [_ | _]), do: :ok
  defp ensure_consistent_history!(_module, %Snapshot{rebaseline?: true}, []), do: :ok

  defp ensure_consistent_history!(module, nil, migration_files) when migration_files != [] do
    raise BlueprintError,
      message: """
      Blueprint migration history for #{inspect(module)} is missing its snapshot.

      Found #{length(migration_files)} migration file(s), but no matching snapshot. Restore
      the snapshots from version control. If the database already matches the current
      Blueprint, deliberately re-baseline it as documented in guides/blueprint_migrations.md.
      """
  end

  defp ensure_consistent_history!(module, %Snapshot{}, []) do
    raise BlueprintError,
      message: """
      Blueprint migration history for #{inspect(module)} is missing its migration files.

      Restore the migrations from version control or pass the correct `:migration_path`.
      Generation stopped to avoid emitting an invalid alter migration without its base.
      """
  end

  defp migration_sequence!(filename) do
    filename
    |> Path.basename(".exs")
    |> String.split("_")
    |> List.last()
    |> Integer.parse()
    |> case do
      {sequence, ""} ->
        sequence

      _ ->
        raise BlueprintError,
          message: "Invalid Blueprint migration filename: #{filename}"
    end
  end

  defp build_migration_filename(module, sequence, opts) do
    migration_path = Keyword.fetch!(opts, :migration_path)

    Path.join(
      migration_path,
      "#{next_migration_version(opts)}_#{build_filename_core(module)}_#{sequence}.exs"
    )
  end

  defp build_filename_core(module) do
    naming = module.__naming__()
    String.downcase("blueprint_#{naming.application}_#{naming.domain}_#{naming.schema}")
  end

  defp next_migration_version(opts) do
    latest_version = latest_migration_version(opts)
    version = Keyword.get(opts, :planned_migration_version) || max(current_migration_version(), latest_version + 1)
    if version <= latest_version, do: stale_plan!()

    version
    |> Integer.to_string()
    |> String.pad_leading(14, "0")
  end

  defp current_migration_version do
    DateTime.utc_now() |> Calendar.strftime("%Y%m%d%H%M%S") |> String.to_integer()
  end

  defp latest_migration_version(opts) do
    opts
    |> Keyword.fetch!(:migration_path)
    |> Path.join("*.exs")
    |> Path.wildcard()
    |> Enum.map(&ecto_migration_version!/1)
    |> Enum.max(fn -> 0 end)
  end

  # The first migration of a batch takes the current time; each later one
  # takes the next second, and always follows its own directory's history.
  defp batch_migration_version(previous, opts) do
    floor = if previous, do: following_second(previous), else: current_migration_version()
    max(floor, latest_migration_version(opts) + 1)
  end

  defp following_second(version) do
    with <<year::binary-4, month::binary-2, day::binary-2, hour::binary-2, minute::binary-2, second::binary-2>> <-
           Integer.to_string(version),
         {:ok, time} <- NaiveDateTime.from_iso8601("#{year}-#{month}-#{day}T#{hour}:#{minute}:#{second}") do
      time |> NaiveDateTime.add(1) |> Calendar.strftime("%Y%m%d%H%M%S") |> String.to_integer()
    else
      _ -> version + 1
    end
  end

  defp ecto_migration_version!(filename) do
    filename
    |> Path.basename()
    |> String.split("_", parts: 2)
    |> hd()
    |> Integer.parse()
    |> case do
      {version, ""} ->
        version

      _ ->
        raise BlueprintError,
          message: "Invalid Ecto migration filename in Blueprint migration path: #{filename}"
    end
  end

  defp with_migration_lock(opts, fun) do
    resource = {__MODULE__, Path.expand(Keyword.fetch!(opts, :migration_path))}
    :global.trans({resource, self()}, fun)
  end

  defp pad_sequence(number), do: number |> to_string() |> String.pad_leading(3, "0")

  defp format_code(content) do
    content
    |> Code.format_string!(locals_without_parens: locals_without_parens())
    |> IO.iodata_to_binary()
  end

  defp atomic_write!(filename, contents) do
    suffix = :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
    temporary = "#{filename}.tmp.#{suffix}"

    try do
      File.write!(temporary, contents, [:sync, :exclusive])
      File.ln!(temporary, filename)
    after
      File.rm(temporary)
    end
  end

  defp raise_unsupported_change!(module, {:table_changed, previous, current}) do
    raise BlueprintError,
      message: """
      Blueprint #{inspect(module)} changed its table from #{inspect(previous)} to #{inspect(current)}.

      Generate a hand-written migration that renames the table, then deliberately
      re-baseline the Blueprint snapshot as documented in guides/blueprint_migrations.md.
      """
  end

  defp raise_unsupported_change!(module, {:primary_key_changed, previous, current}) do
    raise BlueprintError,
      message: """
      Blueprint #{inspect(module)} changed its primary key from #{inspect(previous)} to #{inspect(current)}.

      Primary-key changes cannot be inferred safely. Create and test a hand-written
      migration, then deliberately re-baseline the Blueprint snapshot as documented
      in guides/blueprint_migrations.md.
      """
  end

  defp raise_unsupported_change!(module, {:column_primary_keys_changed, previous, current}) do
    raise BlueprintError,
      message: """
      Blueprint #{inspect(module)} changed its relation primary-key columns from #{inspect(previous)} to #{inspect(current)}.

      Composite primary-key changes cannot be inferred safely. Create and test a
      hand-written migration, then deliberately re-baseline the Blueprint snapshot
      as documented in guides/blueprint_migrations.md.
      """
  end

  defp raise_unsupported_change!(module, reason) do
    raise BlueprintError,
      message: "Cannot generate migration for #{inspect(module)}: #{inspect(reason)}"
  end

  defp locals_without_parens do
    path = Path.join(File.cwd!(), "deps/ecto_sql/.formatter.exs")

    if File.exists?(path) do
      {formatter_opts, _} = Code.eval_file(path)
      Keyword.get(formatter_opts, :locals_without_parens, [])
    else
      []
    end
  end
end

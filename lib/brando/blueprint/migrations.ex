defmodule Brando.Blueprint.Migrations do
  @moduledoc """
  Generates reviewed, reversible Ecto migrations from Blueprint storage schemas.

  Migration generation compares normalized storage snapshots rather than live
  DSL structs. Unsupported table and primary-key changes fail explicitly and
  must be handled by a hand-written migration.
  """

  alias Brando.Blueprint.Migrations.{Diff, Renderer, Schema}
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
    refuse_embedded!(module, "generate a migration for")
    opts = Keyword.merge(@default_opts, opts)

    with_migration_lock(opts, fn ->
      Snapshot.with_lock(module, opts, fn ->
        do_create_migration(module, opts)
      end)
    end)
  end

  @doc """
  Stores the current Blueprint schema as the next snapshot without generating a migration.

  This is an explicit recovery tool for a storage change already implemented by a
  reviewed hand-written migration. It must only be run after the database migration
  has been created and tested.
  """
  @spec rebaseline_snapshot(module(), keyword()) :: {:ok, map()}
  def rebaseline_snapshot(module, opts \\ @default_opts) do
    refuse_embedded!(module, "rebaseline")
    opts = Keyword.merge(@default_opts, opts)

    Snapshot.with_lock(module, opts, fn ->
      version = Snapshot.get_snapshot_version(module, opts) + 1
      snapshot = %{Snapshot.build_snapshot(module, version) | rebaseline?: true}
      {:ok, filename} = Snapshot.store_snapshot(snapshot, module, opts)

      {:ok, %{module: module, snapshot: filename, snapshot_version: version}}
    end)
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
    if function_exported?(module, :__data_layer__, 0) and module.__data_layer__() == :embedded do
      raise BlueprintError, """
      Cannot #{action} #{inspect(module)}: it declares `data_layer :embedded`.

      Embedded Blueprints have no table of their own — their storage belongs to
      the Blueprint that embeds them. Generate that Blueprint's migration instead.
      """
    end
  end

  defp do_create_migration(module, opts) do
    previous_snapshot = Snapshot.get_latest_snapshot(module, opts)
    ensure_consistent_history!(module, previous_snapshot, migration_files(module, opts))
    current_schema = Schema.build(module)

    case Diff.compare(current_schema, snapshot_schema(previous_snapshot)) do
      {:ok, diff} ->
        if Diff.empty?(diff) do
          upgrade_snapshot_format(module, previous_snapshot, current_schema, opts)

          {:noop,
           %{
             module: module,
             message: "No storage changes necessary",
             snapshot_version: snapshot_version(previous_snapshot)
           }}
        else
          write_migration_and_snapshot(module, diff, current_schema, previous_snapshot, opts)
        end

      {:error, reason} ->
        raise_unsupported_change!(module, reason)
    end
  end

  defp write_migration_and_snapshot(module, diff, current_schema, previous_snapshot, opts) do
    sequence = get_sequence(module, opts)
    snapshot_version = snapshot_version(previous_snapshot) + 1

    contents =
      module
      |> Renderer.render(sequence, diff, current_schema, snapshot_schema(previous_snapshot))
      |> format_code()

    migration_filename = build_migration_filename(module, sequence, opts)
    snapshot = Snapshot.build_snapshot(module, snapshot_version)

    atomic_write!(migration_filename, contents)

    try do
      {:ok, snapshot_filename} = Snapshot.store_snapshot(snapshot, module, opts)

      {:ok,
       %{
         module: module,
         migration: migration_filename,
         snapshot: snapshot_filename,
         sequence: sequence,
         snapshot_version: snapshot_version,
         destructive_operations: Diff.destructive_operations(diff)
       }}
    rescue
      error ->
        File.rm(migration_filename)
        reraise error, __STACKTRACE__
    end
  end

  defp upgrade_snapshot_format(_module, nil, _current_schema, _opts), do: :ok

  defp upgrade_snapshot_format(_module, %Snapshot{migrated_from_format: nil}, _current_schema, _opts), do: :ok

  defp upgrade_snapshot_format(module, %Snapshot{} = previous_snapshot, current_schema, opts) do
    upgraded = %Snapshot{
      previous_snapshot
      | format_version: 3,
        migrated_from_format: nil,
        schema: Schema.persistable(current_schema),
        updated_at: DateTime.utc_now(),
        attributes: nil,
        assets: nil,
        relations: nil,
        traits: nil
    }

    Snapshot.store_snapshot(upgraded, module, opts)
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

  defp migration_files(module, opts) do
    filename_core = build_filename_core(module)
    migration_path = Keyword.fetch!(opts, :migration_path)
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
    File.mkdir_p!(migration_path)

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
    current_version = DateTime.utc_now() |> Calendar.strftime("%Y%m%d%H%M%S") |> String.to_integer()

    latest_version =
      opts
      |> Keyword.fetch!(:migration_path)
      |> Path.join("*.exs")
      |> Path.wildcard()
      |> Enum.map(&ecto_migration_version!/1)
      |> Enum.max(fn -> 0 end)

    max(current_version, latest_version + 1)
    |> Integer.to_string()
    |> String.pad_leading(14, "0")
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
    temporary = "#{filename}.tmp.#{System.unique_integer([:positive, :monotonic])}"

    try do
      File.write!(temporary, contents, [:sync])
      File.rename!(temporary, filename)
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

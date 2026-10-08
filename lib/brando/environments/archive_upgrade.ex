defmodule Brando.Environments.ArchiveUpgrade do
  @moduledoc """
  Brings an archive restored as a new environment up to the structure the
  site's other environments have, or refuses to restore it.

  Some of Brando's upgrade migrations change every environment schema in the
  run that migrates `public` (their source loops over the `tenant_*`
  schemas). Archive schemas (`tenant_<site>_<env>_archive_<timestamp>`) are
  snapshots and are left out of that loop, so an archive taken before such a
  migration ran lacks what it added. Restoring it as it is would give an
  environment that Brando's code cannot read.

  Restoring therefore:

    1. Plans before anything changes (`plan/2`). A public migration that
       loops over environments and ran after the archive was taken (by its
       `schema_migrations` time against the archive's timestamp) was missed
       by the archive. A missed Brando migration whose current template can
       run for one environment is replayed; any other missed migration,
       Brando's older ones or the application's own, refuses the restore.
    2. Replays the missed migrations in the restored schema only
       (`replay/2`), oldest first, from Brando's current templates. Each
       is recorded in the environment's own `schema_migrations`.
    3. After the environment's tenant migrations, compares its tables,
       columns and indexes with the live environment's (`missing/2`).
       Anything missing refuses the restore, which is then undone.

  `Brando.Environments.rollback/2` removes the new environment again when
  replaying or the comparison fails, so a restore either ends up to date or
  leaves nothing behind.

  The public migrations are read from the repository's migrations directory,
  or from `config :brando, :public_migrations_path`. Replays go through
  `Ecto.Migrator.up/4`, or `config :brando, :archive_upgrade_migrator`: the
  restore holds a connection for the site's lock, which the test sandbox's
  single connection cannot spare.
  """

  alias Brando.Migration.TemplateDrift
  alias Brando.Tenant.SharedTables

  # The query a migration uses to find the environment schemas
  @environment_loop "nspname ~ '^tenant_"
  # How a template runs for the one environment the migrator names
  @single_environment ~r/case prefix\(\) do\s+"tenant_" <> _ = \w+ ->\s+\[\w+\]/

  @typedoc "A missed migration: its version, name and Brando's template"
  @type replay :: {integer(), String.t(), Path.t()}

  @doc """
  The migrations the archive missed that can be replayed in it, or the ones
  that cannot, as `{:error, {:archive_behind, {:migrations, names}}}`.
  """
  @spec plan(String.t(), keyword()) :: {:ok, [replay()]} | {:error, term()}
  def plan(archive_schema, opts \\ []) do
    directory = opts[:migrations_path] || migrations_path()
    templates_dir = opts[:templates_dir] || TemplateDrift.templates_dir()

    case taken_at(archive_schema) do
      nil ->
        {:error, {:archive_behind, :unknown_age}}

      taken_at ->
        {replays, blocking} =
          directory
          |> missed(taken_at)
          |> Enum.map(fn {version, name} -> {version, name, Path.join(templates_dir, name <> ".exs")} end)
          |> Enum.split_with(fn {_version, _name, template} -> single_environment?(template) end)

        if blocking == [],
          do: {:ok, replays},
          else: {:error, {:archive_behind, {:migrations, Enum.map(blocking, &elem(&1, 1))}}}
    end
  end

  @doc """
  When the archive was taken: the timestamp in its name, which is set just
  before the environment is copied into it.
  """
  @spec taken_at(String.t()) :: NaiveDateTime.t() | nil
  def taken_at(archive_schema) do
    with [_, timestamp] <- Regex.run(~r/_archive_(\d{14})(?:_[a-f0-9]{8})?$/, archive_schema),
         <<y::binary-4, mo::binary-2, d::binary-2, h::binary-2, mi::binary-2, s::binary-2>> = timestamp,
         {:ok, taken_at} <- NaiveDateTime.from_iso8601("#{y}-#{mo}-#{d}T#{h}:#{mi}:#{s}") do
      taken_at
    else
      _ -> nil
    end
  end

  # Public migrations that loop over the environment schemas and ran at or
  # after `taken_at`, oldest first
  defp missed(directory, taken_at) do
    ran_since =
      "SELECT version FROM #{migration_source()} WHERE inserted_at >= $1"
      |> query!([taken_at])
      |> Enum.map(&hd/1)
      |> MapSet.new()

    for path <- Path.wildcard(Path.join(directory, "*.exs")),
        {version, "_" <> name} <- [Integer.parse(Path.basename(path, ".exs"))],
        MapSet.member?(ran_since, version),
        File.read!(path) =~ @environment_loop do
      {version, name}
    end
    |> Enum.sort()
  end

  defp single_environment?(template), do: File.exists?(template) and File.read!(template) =~ @single_environment

  @doc """
  Runs each migration in `replays` in the `prefix` schema only. Returns
  `{:error, {name, reason}}` for the first that fails.
  """
  @spec replay([replay()], String.t()) :: :ok | {:error, {String.t(), term()}}
  def replay(replays, prefix) do
    Enum.reduce_while(replays, :ok, fn {version, name, template}, :ok ->
      case run(version, template, prefix) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {name, reason}}}
      end
    end)
  end

  defp run(version, template, prefix) do
    # The application's copy of the migration has the same module name and
    # may be loaded; the template replaces it for this run
    for [_, name] <- Regex.scan(~r/^defmodule ([\w.]+) do/m, File.read!(template)) do
      module = Module.concat([name])
      :code.purge(module)
      :code.delete(module)
    end

    modules = Code.compile_file(template)
    migration = Enum.find_value(modules, fn {module, _} -> function_exported?(module, :__migration__, 0) && module end)

    try do
      # The schema is new and the site is locked: nothing else migrates it
      case migrator().up(Brando.Repo.repo(), version, migration, prefix: prefix, migration_lock: false, log: false) do
        result when result in [:ok, :already_up] -> :ok
        other -> {:error, other}
      end
    rescue
      exception -> {:error, Exception.message(exception)}
    catch
      kind, reason -> {:error, {kind, reason}}
    after
      for {module, _} <- modules do
        :code.purge(module)
        :code.delete(module)
      end
    end
  end

  @doc """
  What `reference` has that `prefix` lacks: tables (`"pages"`), columns, or
  columns of another type (`"pages.meta_nosnippet"`), and indexes
  (`"pages_uri_index"`). Shared tables are left out; extra tables and
  columns in `prefix` are fine.
  """
  @spec missing(String.t(), String.t()) :: [String.t()]
  def missing(prefix, reference) do
    have = structure(prefix)
    want = structure(reference)

    tables_and_columns =
      want.columns
      |> Enum.sort()
      |> Enum.flat_map(fn {table, columns} -> missing_columns(table, columns, have.columns[table]) end)

    tables_and_columns ++ Enum.sort(MapSet.to_list(MapSet.difference(want.indexes, have.indexes)))
  end

  defp missing_columns(table, _columns, nil), do: [table]

  defp missing_columns(table, columns, present),
    do: for({column, _type} = definition <- columns, definition not in present, do: "#{table}.#{column}")

  defp structure(schema) do
    columns =
      "SELECT table_name, column_name, data_type FROM information_schema.columns WHERE table_schema = $1"
      |> query!([schema])
      |> Enum.reject(fn [table | _] -> SharedTables.member?(table) end)
      |> Enum.group_by(&hd/1, fn [_table, column, type] -> {column, type} end)

    indexes =
      "SELECT tablename, indexname FROM pg_indexes WHERE schemaname = $1"
      |> query!([schema])
      |> Enum.reject(fn [table, _index] -> SharedTables.member?(table) end)
      |> MapSet.new(fn [_table, index] -> index end)

    %{columns: columns, indexes: indexes}
  end

  defp query!(sql, params), do: Ecto.Adapters.SQL.query!(Brando.Repo.repo(), sql, params).rows

  defp migration_source, do: Brando.Repo.repo().config()[:migration_source] || "schema_migrations"

  defp migrator, do: Brando.config(:archive_upgrade_migrator) || Ecto.Migrator

  defp migrations_path,
    do: Brando.config(:public_migrations_path) || Ecto.Migrator.migrations_path(Brando.Repo.repo())
end

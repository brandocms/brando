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

    1. Plans before anything changes (`plan/2`). Every public migration
       that ran after the archive was taken (by its `schema_migrations` time
       against the archive's timestamp) must be found among the migration
       files and classified:

         * a copy of one of Brando's templates that can run for one
           environment is replayed, as long as it is one of the versions of
           that template Brando has shipped (compared as code: layout,
           comments, docs and module names do not count; see
           `shipped_versions/1`);
         * one that does not touch the environment schemas is left alone;
         * anything else refuses the restore: a migration that touches them
           and cannot be replayed (Brando's older ones, or the application's
           own), a copy of a replayable template that the application changed
           (`"<name> (differs from Brando's template)"`: the replay runs the
           current template, so a backfill added to the copy would be
           skipped), a version without a file, or a missing migrations
           directory.

       Versions recorded before the archive was taken, or with no time (as
       loaded from a structure dump), are not looked at, so migration files
       deleted or squashed since do not matter.

    2. Replays the missed migrations in the restored schema only
       (`replay/2`), oldest first, from Brando's current templates. Each
       is recorded in the environment's own `schema_migrations`.
    3. After the environment's tenant migrations, compares it with the live
       environment (`missing/2`). Anything missing refuses the restore,
       which is then undone.

  `Brando.Environments.rollback/2` removes the new environment again when any
  step after its creation fails or raises, so a restore either ends up to
  date or leaves nothing behind.

  The public migrations are read from the repository's migrations
  directory, and its subdirectories. An application that keeps them
  elsewhere, or in more than one place, sets
  `config :brando, :public_migrations_path` to a path or a list of paths.
  """

  require Logger

  alias Brando.Migration.TemplateDrift
  alias Brando.Tenant.SharedTables

  # What a migration that touches the environment schemas has in it: the
  # query that finds them, Brando's tenant helpers, or a loop over prefixes
  @touches_environments ~r/pg_namespace|tenant_|Brando\.Tenant|prefixes\(/
  # How a template runs for the one environment the migrator names
  @single_environment ~r/case prefix\(\) do\s+"tenant_" <> _ = \w+ ->\s+\[\w+\]/
  # Postgres' "already exists" errors
  @already_exists [:duplicate_table, :duplicate_column, :duplicate_object]

  @typedoc """
  A missed migration: its version, name and Brando's template, and whether
  it ran in the same second the archive was taken, so the archive may
  already have it
  """
  @type replay :: %{version: integer(), name: String.t(), template: Path.t(), same_second?: boolean()}

  # Replays go through Ecto.Migrator. Brando's own tests swap it: a restore
  # holds a connection for the site's lock, which the sandbox's one
  # connection cannot spare for the migrator's task. Compiled out elsewhere.
  if Mix.env() == :test do
    defp migrator, do: Application.get_env(:brando, :archive_upgrade_migrator) || Ecto.Migrator
  else
    defp migrator, do: Ecto.Migrator
  end

  @doc """
  The migrations the archive missed, all of which can be replayed in it, or
  why it cannot be restored: `{:error, {:archive_behind, reason}}`, where
  `reason` is `{:migrations, names}`, `{:migrations_path, path}` or
  `:unknown_age`.
  """
  @spec plan(String.t(), keyword()) :: {:ok, [replay()]} | {:error, term()}
  def plan(archive_schema, opts \\ []) do
    paths = List.wrap(opts[:migrations_path] || migrations_paths())
    templates_dir = opts[:templates_dir] || TemplateDrift.templates_dir()

    with {:ok, taken_at} <- fetch_taken_at(archive_schema),
         {:ok, files} <- migration_files(paths) do
      {replays, blocking} =
        taken_at
        |> ran_since()
        |> Enum.map(&classify(&1, files, templates_dir, taken_at))
        |> Enum.reject(&(&1 == :public))
        |> Enum.split_with(&match?({:replay, _}, &1))

      if blocking == [],
        do: {:ok, Enum.map(replays, &elem(&1, 1))},
        else: {:error, {:archive_behind, {:migrations, Enum.map(blocking, &elem(&1, 1))}}}
    end
  end

  defp fetch_taken_at(archive_schema) do
    case taken_at(archive_schema) do
      nil -> {:error, {:archive_behind, :unknown_age}}
      taken_at -> {:ok, taken_at}
    end
  end

  @doc """
  When the archive was taken: the timestamp in its name, which is set just
  before the environment is copied into it.
  """
  @spec taken_at(String.t()) :: NaiveDateTime.t() | nil
  def taken_at(archive_schema) do
    with [_, y, mo, d, h, mi, s] <-
           Regex.run(~r/_archive_(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(?:_[a-f0-9]{8})?$/, archive_schema),
         {:ok, taken_at} <- NaiveDateTime.from_iso8601("#{y}-#{mo}-#{d}T#{h}:#{mi}:#{s}") do
      taken_at
    else
      _ -> nil
    end
  end

  # Every migration file under the paths, by version
  defp migration_files(paths) do
    case Enum.reject(paths, &File.dir?/1) do
      [] ->
        files =
          for path <- Enum.flat_map(paths, &Path.wildcard(Path.join(&1, "**/*.exs"))),
              {version, "_" <> name} <- [Integer.parse(Path.basename(path, ".exs"))],
              reduce: %{} do
            files -> Map.update(files, version, [{name, path}], &[{name, path} | &1])
          end

        {:ok, files}

      [missing | _] ->
        {:error, {:archive_behind, {:migrations_path, missing}}}
    end
  end

  # Public migrations that ran at or after `taken_at`, oldest first. Ecto
  # records `inserted_at` in UTC, as the archive's name is, to the second;
  # a version without one (loaded from a structure dump) is older.
  defp ran_since(taken_at) do
    "SELECT version, inserted_at FROM #{migration_source()} WHERE inserted_at >= $1 ORDER BY version"
    |> query!([taken_at])
    |> Enum.map(&List.to_tuple/1)
  end

  defp classify({version, inserted_at}, files, templates_dir, taken_at) do
    case files[version] do
      [{name, path}] ->
        template = Path.join(templates_dir, name <> ".exs")

        cond do
          single_environment?(template) and copy_of?(path, template) ->
            same_second? = NaiveDateTime.compare(NaiveDateTime.truncate(inserted_at, :second), taken_at) == :eq
            {:replay, %{version: version, name: name, template: template, same_second?: same_second?}}

          # The replay would run the current template, and what the
          # application changed in its copy (a data backfill, say) would be
          # skipped
          single_environment?(template) ->
            Logger.warning(
              "[Brando.Environments] #{path} is not a version of Brando's template #{template}, " <>
                "which a restored archive would run in its place; the restore is refused"
            )

            {:blocking, "#{name} (differs from Brando's template)"}

          File.read!(path) =~ @touches_environments ->
            {:blocking, name}

          true ->
            :public
        end

      nil ->
        {:blocking, "#{version} (no migration file)"}

      several ->
        {:blocking, "#{version} (#{length(several)} files)"}
    end
  end

  defp single_environment?(template), do: File.regular?(template) and File.read!(template) =~ @single_environment

  @doc """
  Every version of the single-environment `template` Brando has shipped,
  the current one included: the files in
  `priv/templates/brando.upgrade/history/<name>/`, beside the templates
  directory.

  An application's copy is whichever version was current when
  `mix brando.gen.migrations` copied it, and is never updated. A restore
  replays the current template whichever version the application ran: only
  the current one is written to run for one environment (earlier ones loop
  over every environment, or, for a few versions that were on main briefly,
  use the migrator's default prefix only). Every shipped version is accepted
  on purpose, those early ones included: the current template may add
  columns the copy never added, which the comparison with the live
  environment accepts, since a restored environment may have more than the
  live one. What a restore must not do is replay over a copy the application
  changed. So a template whose code changes keeps its earlier versions here,
  and a test fails until the new one is added too.
  """
  @spec shipped_versions(Path.t()) :: [Path.t()]
  def shipped_versions(template) do
    name = Path.basename(template, ".exs")
    history = Path.join([template |> Path.dirname() |> Path.dirname(), "history", name])
    [template | history |> Path.join("*.exs") |> Path.wildcard() |> Enum.sort()]
  end

  @doc """
  Whether two migrations' sources have the same code. Layout, comments,
  trailing whitespace, docs and module names do not count: older versions of
  `mix brando.gen.migrations` put the copy in the application's namespace,
  and the replay renames the module anyway.
  """
  @spec same_code?(String.t(), String.t()) :: boolean()
  def same_code?(source, other), do: as_replayed(source) == as_replayed(other)

  defp copy_of?(path, template) do
    copy = as_replayed(File.read!(path))
    Enum.any?(shipped_versions(template), &(as_replayed(File.read!(&1)) == copy))
  end

  defp as_replayed(code) do
    code
    |> String.replace(~r/[ \t]+$/m, "")
    |> TemplateDrift.normalize()
    |> Macro.postwalk(fn
      {:defmodule, meta, [_name | rest]} -> {:defmodule, meta, [:module | rest]}
      {:__block__, meta, expressions} -> {:__block__, meta, Enum.reject(expressions, &doc?/1)}
      node -> node
    end)
  end

  defp doc?({:@, _, [{doc, _, _}]}), do: doc in [:moduledoc, :doc]
  defp doc?(_expression), do: false

  @doc """
  Runs each migration in `replays` in the `prefix` schema only. Returns
  `{:error, {name, reason}}` for the first that fails.

  A migration that ran in the same second the archive was taken, and fails
  because what it creates already exists, was in the archive already: its
  transaction is rolled back and it is skipped. The comparison with the live
  environment afterwards still has the last word.
  """
  @spec replay([replay()], String.t()) :: :ok | {:error, {String.t(), term()}}
  def replay(replays, prefix) do
    Enum.reduce_while(replays, :ok, fn replay, :ok ->
      case run(replay, prefix) do
        :ok ->
          {:cont, :ok}

        {:error, %Postgrex.Error{postgres: %{code: code}}} when replay.same_second? and code in @already_exists ->
          Logger.info("[Brando.Environments] #{replay.name} was in the archive already; not replayed in #{prefix}")
          {:cont, :ok}

        {:error, reason} ->
          {:halt, {:error, {replay.name, describe(reason)}}}
      end
    end)
  end

  defp describe(exception) when is_exception(exception), do: Exception.message(exception)
  defp describe(reason), do: reason

  # Compiles the template under a module name of its own, so neither a
  # loaded copy of the application's migration nor a replay running for
  # another site at the same time is touched
  defp run(%{version: version, template: template}, prefix) do
    suffix = "ArchiveReplay#{System.unique_integer([:positive])}"

    {source, modules} =
      template
      |> File.read!()
      |> rename_modules(suffix)

    try do
      migration =
        source
        |> Code.compile_string(template)
        |> Enum.find_value(fn {module, _} -> function_exported?(module, :__migration__, 0) && module end)

      # The schema is new and the site is locked: nothing else migrates it
      case migration &&
             migrator().up(Brando.Repo.repo(), version, migration, prefix: prefix, migration_lock: false, log: false) do
        nil -> {:error, "no migration in #{Path.basename(template)}"}
        result when result in [:ok, :already_up] -> :ok
        other -> {:error, other}
      end
    rescue
      exception -> {:error, exception}
    catch
      kind, reason -> {:error, {kind, reason}}
    after
      for module <- modules do
        :code.purge(module)
        :code.delete(module)
      end
    end
  end

  defp rename_modules(source, suffix) do
    names = for [_, name] <- Regex.scan(~r/^defmodule ([\w.]+) do/m, source), do: name
    renamed = Regex.replace(~r/^defmodule ([\w.]+) do/m, source, "defmodule \\1.#{suffix} do")
    {renamed, Enum.map(names, &Module.concat([&1, suffix]))}
  end

  @doc """
  What `reference` has that `prefix` lacks, ignoring names and which schema
  they are in:

    * tables (`"pages"`), and columns that are missing or differ in type,
      nullability or default (`"pages.meta_nosnippet"`);
    * indexes, by what they cover (`"index on pages (uri)"`);
    * foreign keys (`"foreign key on note_mentions (note_id) to entry_notes (id)"`)
      and unique constraints, primary keys included
      (`"unique on pages (id)"`).

  Shared tables are left out; extra tables, columns and indexes in `prefix`
  are fine.
  """
  @spec missing(String.t(), String.t()) :: [String.t()]
  def missing(prefix, reference) do
    have = structure(prefix)
    want = structure(reference)

    tables_and_columns =
      want.columns
      |> Enum.sort()
      |> Enum.flat_map(fn {table, columns} -> missing_columns(table, columns, have.columns[table]) end)

    others = for key <- [:indexes, :constraints], item <- MapSet.difference(want[key], have[key]), do: item
    tables_and_columns ++ Enum.sort(others)
  end

  defp missing_columns(table, _columns, nil), do: [table]

  defp missing_columns(table, columns, present),
    do: for({column, _type, _null, _default} = definition <- columns, definition not in present, do: "#{table}.#{column}")

  defp structure(schema) do
    columns =
      """
      SELECT table_name, column_name, data_type, is_nullable, column_default
      FROM information_schema.columns WHERE table_schema = $1
      """
      |> query!([schema])
      |> Enum.reject(fn [table | _] -> SharedTables.member?(table) end)
      |> Enum.group_by(&hd/1, fn [_table, column, type, null, default] ->
        {column, type, null, unqualify(default, schema)}
      end)

    indexes =
      "SELECT tablename, indexdef FROM pg_indexes WHERE schemaname = $1"
      |> query!([schema])
      |> Enum.reject(fn [table, _definition] -> SharedTables.member?(table) end)
      |> MapSet.new(fn [table, definition] -> index(schema, table, definition) end)

    %{columns: columns, indexes: indexes, constraints: constraints(schema)}
  end

  # `CREATE UNIQUE INDEX name ON schema.pages USING btree (uri)` is
  # `"unique index on pages (uri)"`, whatever its name and schema. A name or
  # schema with spaces is quoted, so the definition is cut at the first
  # ` ON ` outside quotes; a definition that cannot be read is kept whole.
  defp index(schema, table, definition) do
    case Regex.run(~r/^CREATE (UNIQUE )?INDEX (?:"(?:[^"]|"")*"|\S)+ ON (?:"(?:[^"]|"")*"|[^\s"])+ (.*)$/s, definition) do
      [_, unique, covers] ->
        covers = covers |> String.replace_prefix("USING btree ", "") |> unqualify(schema)
        "#{String.downcase(unique)}index on #{table} #{covers}"

      _ ->
        "index on #{table}: #{unqualify(definition, schema)}"
    end
  end

  defp constraints(schema) do
    """
    SELECT rel.relname, c.contype, ref_ns.nspname, ref.relname,
      ARRAY(SELECT a.attname FROM unnest(c.conkey) WITH ORDINALITY k(attnum, n)
            JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum ORDER BY k.n),
      ARRAY(SELECT a.attname FROM unnest(c.confkey) WITH ORDINALITY k(attnum, n)
            JOIN pg_attribute a ON a.attrelid = c.confrelid AND a.attnum = k.attnum ORDER BY k.n)
    FROM pg_constraint c
    JOIN pg_class rel ON rel.oid = c.conrelid
    JOIN pg_namespace ns ON ns.oid = rel.relnamespace
    LEFT JOIN pg_class ref ON ref.oid = c.confrelid
    LEFT JOIN pg_namespace ref_ns ON ref_ns.oid = ref.relnamespace
    WHERE ns.nspname = $1 AND c.contype IN ('f', 'u', 'p')
    """
    |> query!([schema])
    |> Enum.reject(fn [table | _] -> SharedTables.member?(table) end)
    |> MapSet.new(fn
      [table, "f", ref_schema, ref_table, columns, ref_columns] ->
        # A key to the environment's own table names it without a schema
        target = if ref_schema == schema, do: ref_table, else: "#{ref_schema}.#{ref_table}"
        "foreign key on #{table} (#{Enum.join(columns, ", ")}) to #{target} (#{Enum.join(ref_columns, ", ")})"

      [table, _unique_or_primary, _, _, columns, _] ->
        "unique on #{table} (#{Enum.join(columns, ", ")})"
    end)
  end

  defp unqualify(nil, _schema), do: nil

  defp unqualify(sql, schema),
    do: sql |> String.replace(~s("#{schema}".), "") |> String.replace("#{schema}.", "")

  defp query!(sql, params), do: Ecto.Adapters.SQL.query!(Brando.Repo.repo(), sql, params).rows

  defp migration_source, do: Brando.Repo.repo().config()[:migration_source] || "schema_migrations"

  defp migrations_paths,
    do: Brando.config(:public_migrations_path) || Ecto.Migrator.migrations_path(Brando.Repo.repo())
end

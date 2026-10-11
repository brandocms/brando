defmodule Brando.Blueprint.Migrations.Reconcile do
  @moduledoc """
  Fits a planned Blueprint migration to a database that already holds some of
  its storage, for `mix brando.gen.blueprint_migration --reconcile`.

  A snapshot older than its database (or a table with no snapshot at all) makes
  the diff propose storage that exists and drops that would lose data. Against
  the tables, columns and indexes the database reports, the diff is changed so
  that:

    * a table the plan creates but the database has becomes an alter that adds
      only what the database lacks, and a table that already has everything
      needs no migration;
    * an existing column, index or auxiliary table the plan adds is guarded
      with `add_if_not_exists`/`create_if_not_exists` and left out of `down/0`;
      an existing column with a foreign key is left out, since PostgreSQL adds
      the named constraint even when it skips the column;
    * a column or auxiliary table that holds data, and a legacy Villain column
      (`data`, `html`, `*_data`, `*_html`), is kept; a drop of something the
      database does not have is left out.

  Only names are compared. Types, defaults and nullability are not checked.
  """

  alias Brando.Blueprint.Migrations.Diff
  alias Brando.Exception.BlueprintError

  @typedoc """
  Text that may give a number of values or rows. The counts change with the
  data, so a plan is fingerprinted with them left out (`without_counts/1`).
  """
  @type text :: String.t() | [String.t() | {:count, non_neg_integer(), :value | :row}]

  @type t :: %__MODULE__{
          create_as_alter?: boolean(),
          guarded_columns: MapSet.t(atom()),
          guarded_indexes: MapSet.t(String.t()),
          guarded_tables: MapSet.t(String.t()),
          relaxed: [String.t()],
          comments: [text()],
          counts?: boolean(),
          summary: %{
            optional(:database) => String.t(),
            table: String.t() | nil,
            create_as_alter?: boolean(),
            guarded: [text()],
            left_out: [text()],
            kept: [text()],
            relaxed: [String.t()]
          }
        }

  @typedoc """
  What was reconciled, for the generator's report: the database read, the
  existing objects guarded with `*_if_not_exists`, the operations left out, and
  the columns and tables kept.
  """
  @type summary :: %{
          optional(:database) => String.t(),
          table: String.t() | nil,
          create_as_alter?: boolean(),
          guarded: [String.t()],
          left_out: [String.t()],
          kept: [String.t()],
          relaxed: [String.t()]
        }

  defstruct create_as_alter?: false,
            guarded_columns: MapSet.new(),
            guarded_indexes: MapSet.new(),
            guarded_tables: MapSet.new(),
            relaxed: [],
            comments: [],
            counts?: true,
            summary: %{table: nil, create_as_alter?: false, guarded: [], left_out: [], kept: [], relaxed: []}

  @doc """
  Whether the migration has work of its own beyond the diff: a kept column's
  NOT NULL to drop.
  """
  @spec operations?(t()) :: boolean()
  def operations?(%__MODULE__{relaxed: relaxed}), do: relaxed != []

  @doc "The same reconciliation, with every count written as `N`."
  @spec without_counts(t()) :: t()
  def without_counts(%__MODULE__{} = reconcile), do: %{reconcile | counts?: false}

  @doc "The comments for the migration."
  @spec comments(t()) :: [String.t()]
  def comments(%__MODULE__{} = reconcile), do: Enum.map(reconcile.comments, &text(&1, reconcile.counts?))

  @doc "The report of what was reconciled."
  @spec summary(t()) :: summary()
  def summary(%__MODULE__{summary: summary, counts?: counts?}) do
    Map.new(summary, fn
      {key, entries} when key in [:guarded, :left_out, :kept] -> {key, Enum.map(entries, &text(&1, counts?))}
      entry -> entry
    end)
  end

  defp text(text, _counts?) when is_binary(text), do: text
  defp text(segments, counts?), do: Enum.map_join(segments, &segment(&1, counts?))

  defp segment({:count, 1, unit}, true), do: "1 #{unit}"
  defp segment({:count, count, unit}, true), do: "#{count} #{unit}s"
  defp segment({:count, _count, unit}, false), do: "N #{unit}s"
  defp segment(text, _counts?), do: text

  @typedoc """
  The storage a generated migration in the Blueprint's history created. Only
  that is ever dropped: whether anything else is empty depends on which
  database was read.
  """
  @type owned :: %{columns: MapSet.t(atom()), tables: MapSet.t(String.t()), timestamps?: boolean()}

  @doc """
  Reads the planned tables from `repo` and returns the diff to render with how
  it was reconciled. The repo must be started; tables are looked up in the
  schemas on its search path.
  """
  @spec reconcile(Diff.t(), map(), module(), owned()) :: {Diff.t(), t()}
  def reconcile(%Diff{} = diff, current, repo, owned) do
    database = read_database(repo, planned_tables(diff, current))

    {diff, reconcile} =
      cond do
        diff.create? and Map.has_key?(database.tables, current.table) ->
          create_as_alter(current, database)

        diff.create? or Map.has_key?(database.tables, current.table) ->
          against_database(diff, current, database, repo, owned)

        true ->
          raise_missing_table!(current.table)
      end

    source = "#{inspect(repo)}, database #{database.name} (schemas: #{Enum.join(database.schemas, ", ")})"

    {diff,
     %{
       reconcile
       | comments: ["Reconciled against #{source}. Its data decided what is kept." | reconcile.comments],
         summary: Map.put(reconcile.summary, :database, source)
     }}
  end

  # Without the table, every drop would look like one of a column that does not
  # exist and be left out of a migration the next database still needs.
  defp raise_missing_table!(table) do
    raise BlueprintError,
      message: """
      --reconcile compares the plan with the database, but #{table} is not in it, although
      the Blueprint's snapshot history says it was created. Run the existing migrations
      first (mix brando.migrate), or plan without --reconcile.
      """
  end

  @doc "Whether a column name looks like one of the legacy Villain columns the blocks conversion reads."
  @spec villain_column?(atom() | String.t()) :: boolean()
  def villain_column?(column) do
    name = to_string(column)
    name in ["data", "html"] or String.ends_with?(name, "_data") or String.ends_with?(name, "_html")
  end

  # The plan creates a table that already exists: the table predates the
  # Blueprint's snapshots. Add only the columns, indexes and auxiliary tables
  # the database lacks.
  defp create_as_alter(current, database) do
    table = current.table
    columns = Map.fetch!(database.columns, table)
    ensure_primary_key!(current, columns)
    indexes = all_indexes(database)
    {existing_tables, new_tables} = Enum.split_with(current.auxiliary_tables, &Map.has_key?(database.tables, &1.name))

    add_columns = Enum.reject(current.columns, &MapSet.member?(columns, to_string(&1.name)))

    add_indexes =
      Enum.reject(current.indexes ++ Enum.flat_map(existing_tables, & &1.indexes), &MapSet.member?(indexes, &1.name))

    timestamps =
      if current.timestamps and not Enum.any?(~w(inserted_at updated_at), &MapSet.member?(columns, &1)),
        do: :add,
        else: :unchanged

    diff = %Diff{
      add_columns: add_columns,
      add_indexes: add_indexes,
      add_auxiliary_tables: new_tables,
      timestamps: timestamps
    }

    comment =
      "#{table} predates this Blueprint's snapshots, so this migration adds only what the database lacks."

    unconstrained =
      for column <- current.columns,
          column not in add_columns,
          missing = missing_foreign_key(table, column, database),
          missing != [],
          do: {"#{table}.#{column.name} (exists, without its foreign key)", missing}

    {diff,
     %__MODULE__{
       create_as_alter?: true,
       comments: [comment | for({_, missing} <- unconstrained, {:comment, text} <- missing, do: text)],
       summary: %{
         table: table,
         create_as_alter?: true,
         guarded: [],
         left_out: Enum.map(unconstrained, &elem(&1, 0)),
         kept: [],
         relaxed: []
       }
     }}
  end

  defp missing_foreign_key(_table, %{reference: nil}, _database), do: []

  defp missing_foreign_key(table, column, database) do
    name = Map.get(column.reference, :name)

    if is_nil(name) or MapSet.member?(Map.get(database.foreign_keys, table, MapSet.new()), name),
      do: [],
      else: [
        {:comment,
         "#{table}.#{column.name} already exists without the foreign key #{name}, so this migration leaves it out. Add the constraint by hand if the Blueprint needs it."}
      ]
  end

  defp ensure_primary_key!(%{primary_key: %{name: name}, table: table}, columns) do
    unless MapSet.member?(columns, to_string(name)) do
      raise BlueprintError,
        message: """
        #{table} exists without the Blueprint's primary key column #{inspect(name)}.
        --reconcile does not change primary keys. Write that migration by hand, then
        record the Blueprint with --rebaseline as described in guides/blueprint_migrations.md.
        """
    end
  end

  defp ensure_primary_key!(_current, _columns), do: :ok

  defp against_database(diff, current, database, repo, owned) do
    table = current.table
    columns = Map.get(database.columns, table, MapSet.new())

    {remove_columns, column_notes} =
      reconcile_removed_columns(diff.remove_columns, table, columns, database, repo, owned.columns)

    {timestamps, timestamp_notes} =
      reconcile_timestamps(diff.timestamps, table, columns, database, repo, owned.timestamps?)

    {remove_indexes, index_notes} = reconcile_removed_indexes(diff.remove_indexes, all_indexes(database))
    {remove_tables, table_notes} = reconcile_removed_tables(diff.remove_auxiliary_tables, database, repo, owned.tables)

    dropped_tables = MapSet.new(remove_tables, & &1.name)

    existing_indexes =
      database
      |> Map.update!(:indexes, &Map.drop(&1, MapSet.to_list(dropped_tables)))
      |> all_indexes()
      |> MapSet.difference(MapSet.new(remove_indexes, & &1.name))

    existing_tables = database.tables |> Map.keys() |> MapSet.new() |> MapSet.difference(dropped_tables)

    {add_columns, add_notes} = reconcile_added_columns(diff.add_columns, table, columns, database)
    {renames, changes, instead, change_notes} = reconcile_renames_and_changes(diff, current, columns)
    add_columns = add_columns ++ instead
    add_notes = add_notes ++ change_notes

    guarded_indexes =
      (diff.add_indexes ++ Enum.flat_map(diff.add_auxiliary_tables, & &1.indexes))
      |> Enum.map(& &1.name)
      |> Enum.filter(&MapSet.member?(existing_indexes, &1))
      |> MapSet.new()

    guarded_tables =
      diff.add_auxiliary_tables |> Enum.map(& &1.name) |> Enum.filter(&MapSet.member?(existing_tables, &1))

    reconciled = %{
      diff
      | add_columns: add_columns,
        change_columns: changes,
        rename_columns: renames,
        remove_columns: remove_columns,
        remove_indexes: remove_indexes,
        remove_auxiliary_tables: remove_tables,
        timestamps: timestamps
    }

    relaxed = relaxed_columns(diff, reconciled, columns, Map.get(database.required, table, MapSet.new()))

    relax_notes =
      Enum.flat_map(relaxed, fn name ->
        [
          {:relaxed, "#{table}.#{name}"},
          {:comment,
           "#{table}.#{name} is NOT NULL without a default and the Blueprint no longer writes it, so this migration drops its NOT NULL to keep inserts working."}
        ]
      end)

    notes = add_notes ++ column_notes ++ timestamp_notes ++ relax_notes ++ index_notes ++ table_notes
    guarded_columns = add_columns |> Enum.map(& &1.name) |> Enum.filter(&MapSet.member?(columns, to_string(&1)))

    guarded =
      Enum.map(guarded_columns, &"#{table}.#{&1}") ++
        Enum.map(guarded_tables, &"table #{&1}") ++
        Enum.map(Enum.sort(guarded_indexes), &"index #{&1}")

    {reconciled,
     %__MODULE__{
       guarded_columns: MapSet.new(guarded_columns),
       guarded_indexes: guarded_indexes,
       guarded_tables: MapSet.new(guarded_tables),
       relaxed: relaxed,
       comments: for({:comment, comment} <- notes, do: comment),
       summary: %{
         table: table,
         create_as_alter?: false,
         guarded: guarded,
         left_out: for({:left_out, entry} <- notes, do: entry),
         kept: for({:kept, entry} <- notes, do: entry),
         relaxed: for({:relaxed, entry} <- notes, do: entry)
       }
     }}
  end

  # The columns the plan dropped but this migration keeps, that an insert
  # leaving them out would fail on.
  defp relaxed_columns(planned, reconciled, columns, required) do
    timestamps = ~w(inserted_at updated_at)

    kept =
      Enum.map(planned.remove_columns -- reconciled.remove_columns, &to_string(&1.name)) ++
        if(planned.timestamps == :remove and reconciled.timestamps == :unchanged, do: timestamps, else: [])

    Enum.filter(kept, &(MapSet.member?(columns, &1) and MapSet.member?(required, &1)))
  end

  # A rename whose source is gone was done by hand, or never had a column to
  # rename; a change to a column the database lacks has nothing to modify.
  # Either way the Blueprint wants the new column, so it is added unless it is
  # already there. Both columns present cannot be settled without the data.
  defp reconcile_renames_and_changes(diff, current, columns) do
    table = current.table
    present? = &MapSet.member?(columns, to_string(&1))
    defined = Map.new(current.columns, &{&1.name, &1})

    {renames, added, notes} =
      Enum.reduce(diff.rename_columns, {[], [], []}, fn {old, new}, {renames, added, notes} ->
        case {present?.(old), present?.(new)} do
          {true, true} ->
            raise_both_columns!(table, old, new)

          {true, false} ->
            {renames ++ [{old, new}], added, notes}

          {false, true} ->
            {renames, added,
             notes ++
               [
                 {:left_out, "rename of #{table}.#{old} to #{new} (#{new} already exists)"},
                 {:comment,
                  "#{table}.#{new} already exists and #{old} does not, so this migration leaves out the rename."}
               ]}

          {false, false} ->
            {renames, added ++ [Map.fetch!(defined, new)],
             notes ++
               [
                 {:comment,
                  "Neither #{table}.#{old} nor #{new} is in the database, so this migration adds #{new} instead of renaming."}
               ]}
        end
      end)

    renamed_to = MapSet.new(diff.rename_columns, &elem(&1, 1))
    added_names = MapSet.new(added, & &1.name)

    {changes, instead, change_notes} =
      Enum.reduce(diff.change_columns, {[], [], []}, fn {_old, new} = change, {changes, instead, notes} ->
        cond do
          MapSet.member?(added_names, new.name) ->
            {changes, instead, notes}

          present?.(new.name) or MapSet.member?(renamed_to, new.name) ->
            {changes ++ [change], instead, notes}

          true ->
            {changes, instead ++ [new],
             notes ++
               [
                 {:comment,
                  "#{table}.#{new.name} is not in the database, so this migration adds it instead of changing it."}
               ]}
        end
      end)

    {renames, changes, added ++ instead, notes ++ change_notes}
  end

  defp raise_both_columns!(table, old, new) do
    raise BlueprintError,
      message: """
      #{table} has both #{old} and #{new}, and the Blueprint renames #{old} to #{new}.
      --reconcile cannot tell which holds the data to keep. Merge them in a
      hand-written migration, then plan again.
      """
  end

  # An existing column with a foreign key is left out: `ADD COLUMN IF NOT
  # EXISTS ... REFERENCES` skips the column but still adds the constraint.
  defp reconcile_added_columns(add_columns, table, columns, database) do
    Enum.flat_map_reduce(add_columns, [], fn column, notes ->
      cond do
        not MapSet.member?(columns, to_string(column.name)) ->
          {[column], notes}

        column.reference ->
          {[], notes ++ reference_notes(table, column, database)}

        true ->
          {[column], notes}
      end
    end)
  end

  defp reference_notes(table, column, database) do
    case missing_foreign_key(table, column, database) do
      [] ->
        [
          {:left_out, "#{table}.#{column.name} (exists with its foreign key)"},
          {:comment, "#{table}.#{column.name} already exists with its foreign key, so this migration leaves it out."}
        ]

      missing ->
        [{:left_out, "#{table}.#{column.name} (exists, without its foreign key)"} | missing]
    end
  end

  defp reconcile_removed_columns(remove_columns, table, columns, database, repo, owned) do
    Enum.flat_map_reduce(remove_columns, [], fn column, notes ->
      name = to_string(column.name)

      cond do
        not MapSet.member?(columns, name) ->
          {[], notes ++ [{:left_out, "drop of #{table}.#{name} (not in the database)"}]}

        not MapSet.member?(owned, column.name) and not villain_column?(name) ->
          {[], notes ++ kept_unowned("#{table}.#{name}")}

        villain_column?(name) ->
          count = count_values(repo, database, table, name)

          {[],
           notes ++
             [
               {:kept, ["#{table}.#{name} (legacy Villain column, ", values(count), ")"]},
               {:comment,
                [
                  "#{table}.#{name} is a legacy Villain column holding ",
                  values(count),
                  "; --reconcile never drops it. Keep it until the blocks conversion is verified on production data."
                ]}
             ]}

        (count = count_values(repo, database, table, name)) > 0 ->
          {[], notes ++ kept_with_data(table, name, count)}

        true ->
          {[column], notes}
      end
    end)
  end

  defp reconcile_timestamps(:remove, table, columns, database, repo, owned?) do
    present = Enum.filter(~w(inserted_at updated_at), &MapSet.member?(columns, &1))

    cond do
      present == [] ->
        {:unchanged, [{:left_out, "drop of #{table} timestamps (not in the database)"}]}

      not owned? ->
        {:unchanged, Enum.flat_map(present, &kept_unowned("#{table}.#{&1}"))}

      true ->
        counts = Enum.map(present, &{&1, count_values(repo, database, table, &1)})

        if Enum.any?(counts, &(elem(&1, 1) > 0)),
          do: {:unchanged, Enum.flat_map(counts, fn {name, count} -> kept_with_data(table, name, count) end)},
          else: {:remove, []}
    end
  end

  defp reconcile_timestamps(:add, table, columns, _database, _repo, _owned?) do
    if Enum.all?(~w(inserted_at updated_at), &MapSet.member?(columns, &1)),
      do: {:unchanged, [{:left_out, "#{table} timestamps (already exist)"}]},
      else: {:add, []}
  end

  defp reconcile_timestamps(timestamps, _table, _columns, _database, _repo, _owned?), do: {timestamps, []}

  defp kept_unowned(name) do
    [
      {:kept, "#{name} (predates the Blueprint's generated migrations)"},
      {:comment,
       "#{name} predates this Blueprint's generated migrations, so --reconcile keeps it whatever it holds. Dropping it is a separate decision."}
    ]
  end

  defp kept_with_data(table, name, count) do
    [
      {:kept, ["#{table}.#{name} (", values(count), ")"]},
      {:comment,
       ["#{table}.#{name} holds ", values(count), ", so this migration keeps it. Dropping it is a separate decision."]}
    ]
  end

  defp reconcile_removed_indexes(remove_indexes, existing) do
    {present, absent} = Enum.split_with(remove_indexes, &MapSet.member?(existing, &1.name))
    {present, Enum.map(absent, &{:left_out, "drop of index #{&1.name} (not in the database)"})}
  end

  defp reconcile_removed_tables(remove_tables, database, repo, owned) do
    Enum.flat_map_reduce(remove_tables, [], fn table, notes ->
      cond do
        not Map.has_key?(database.tables, table.name) ->
          {[], notes ++ [{:left_out, "drop of table #{table.name} (not in the database)"}]}

        not MapSet.member?(owned, table.name) ->
          {[], notes ++ kept_unowned("table #{table.name}")}

        (rows = count_rows(repo, database, table.name)) > 0 ->
          {[],
           notes ++
             [
               {:kept, ["table #{table.name} (", rows(rows), ")"]},
               {:comment,
                ["#{table.name} holds ", rows(rows), ", so this migration keeps it. Dropping it is a separate decision."]}
             ]}

        true ->
          {[table], notes}
      end
    end)
  end

  defp values(count), do: {:count, count, :value}
  defp rows(count), do: {:count, count, :row}

  defp planned_tables(diff, current) do
    Enum.uniq([current.table | Enum.map(diff.add_auxiliary_tables ++ diff.remove_auxiliary_tables, & &1.name)])
  end

  defp all_indexes(database), do: database.indexes |> Map.values() |> Enum.reduce(MapSet.new(), &MapSet.union/2)

  # The tables found, the schema each was found in (the first on the search
  # path), and their column, index and foreign-key names.
  defp read_database(repo, tables) do
    %{rows: [[schemas]]} = repo.query!("SELECT current_schemas(false)::text[]", [], log: false)

    %{rows: rows} =
      repo.query!(
        """
        SELECT DISTINCT ON (table_name) table_name::text, table_schema::text
        FROM information_schema.tables
        WHERE table_schema::text = ANY($1::text[]) AND table_name::text = ANY($2::text[])
        ORDER BY table_name, array_position($1::text[], table_schema::text)
        """,
        [schemas, tables],
        log: false
      )

    found = Map.new(rows, fn [table, schema] -> {table, schema} end)
    %{rows: [[name]]} = repo.query!("SELECT current_database()::text", [], log: false)

    %{
      name: name,
      schemas: schemas,
      tables: found,
      columns: names_by_table(repo, found, columns_query()),
      indexes: names_by_table(repo, found, indexes_query()),
      required: names_by_table(repo, found, required_query()),
      foreign_keys: names_by_table(repo, found, foreign_keys_query())
    }
  end

  defp names_by_table(repo, found, query) do
    Map.new(found, fn {table, schema} ->
      %{rows: rows} = repo.query!(query, [schema, table], log: false)
      {table, MapSet.new(rows, &hd/1)}
    end)
  end

  defp columns_query do
    "SELECT column_name::text FROM information_schema.columns WHERE table_schema::text = $1 AND table_name::text = $2"
  end

  # Columns an insert must give a value for.
  defp required_query do
    """
    SELECT column_name::text FROM information_schema.columns
    WHERE table_schema::text = $1 AND table_name::text = $2
      AND is_nullable = 'NO' AND column_default IS NULL AND is_identity = 'NO' AND is_generated = 'NEVER'
    """
  end

  defp indexes_query, do: "SELECT indexname::text FROM pg_indexes WHERE schemaname = $1 AND tablename = $2"

  defp foreign_keys_query do
    """
    SELECT c.conname::text
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE c.contype = 'f' AND n.nspname = $1 AND t.relname = $2
    """
  end

  defp count_values(repo, database, table, column) do
    count(repo, "SELECT count(#{quote_name(column)}) FROM #{qualified(database, table)}")
  end

  defp count_rows(repo, database, table), do: count(repo, "SELECT count(*) FROM #{qualified(database, table)}")

  defp count(repo, sql) do
    %{rows: [[count]]} = repo.query!(sql, [], log: false)
    count
  end

  defp qualified(database, table), do: "#{quote_name(Map.fetch!(database.tables, table))}.#{quote_name(table)}"

  defp quote_name(name), do: ~s("#{String.replace(name, ~s("), ~s(""))}")
end

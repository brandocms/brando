defmodule Brando.Blueprint.Migrations.Diff do
  @moduledoc false

  alias Brando.Blueprint.Migrations.Schema

  @type t :: %__MODULE__{
          create?: boolean(),
          add_columns: [Schema.column()],
          remove_columns: [Schema.column()],
          change_columns: [{Schema.column(), Schema.column()}],
          rename_columns: [{atom(), atom()}],
          add_indexes: [Schema.index()],
          remove_indexes: [Schema.index()],
          add_auxiliary_tables: [Schema.auxiliary_table()],
          remove_auxiliary_tables: [Schema.auxiliary_table()],
          timestamps: :unchanged | :add | :remove
        }

  defstruct create?: false,
            add_columns: [],
            remove_columns: [],
            change_columns: [],
            rename_columns: [],
            add_indexes: [],
            remove_indexes: [],
            add_auxiliary_tables: [],
            remove_auxiliary_tables: [],
            timestamps: :unchanged

  @doc """
  Compares two normalized Blueprint storage schemas.

  Table and primary-key changes are deliberately rejected. They require an
  explicit hand-written migration because their safe behavior depends on the
  deployed database and cannot be inferred from the Blueprint alone.
  """
  @spec compare(Schema.t(), Schema.t() | nil) :: {:ok, t()} | {:error, term()}
  def compare(current, nil) do
    {:ok,
     %__MODULE__{
       create?: true,
       add_columns: current.columns,
       add_indexes: current.indexes,
       add_auxiliary_tables: current.auxiliary_tables,
       timestamps: if(current.timestamps, do: :add, else: :unchanged)
     }}
  end

  def compare(current, previous) do
    with :ok <- unchanged_identity(current, previous),
         {:ok, rename_columns, matched_previous_names} <- collect_renames(current.columns, previous.columns) do
      {:ok, build_diff(current, previous, rename_columns, matched_previous_names)}
    end
  end

  @doc """
  Returns true when a diff contains no migration operations.
  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{} = diff) do
    operation_groups = [
      diff.add_columns,
      diff.remove_columns,
      diff.change_columns,
      diff.rename_columns,
      diff.add_indexes,
      diff.remove_indexes,
      diff.add_auxiliary_tables,
      diff.remove_auxiliary_tables
    ]

    not diff.create? and diff.timestamps == :unchanged and Enum.all?(operation_groups, &(&1 == []))
  end

  @doc """
  Returns the destructive operations in a diff for reporting and review.
  """
  @spec destructive_operations(t()) :: [term()]
  def destructive_operations(%__MODULE__{} = diff) do
    Enum.map(diff.remove_columns, &{:remove_column, &1.name}) ++
      Enum.map(diff.remove_auxiliary_tables, &{:remove_table, &1.name}) ++
      if(diff.timestamps == :remove, do: [{:remove_timestamps, true}], else: [])
  end

  defp unchanged_identity(current, previous) do
    cond do
      current.table != previous.table ->
        {:error, {:table_changed, previous.table, current.table}}

      current.primary_key != previous.primary_key ->
        {:error, {:primary_key_changed, previous.primary_key, current.primary_key}}

      true ->
        :ok
    end
  end

  defp collect_renames(current_columns, previous_columns) do
    previous_names = MapSet.new(previous_columns, & &1.name)

    current_columns
    |> Enum.reduce_while([], &collect_column_rename(&1, &2, previous_names))
    |> case do
      {:error, _} = error ->
        error

      renames ->
        renames = Enum.reverse(renames)
        {:ok, renames, MapSet.new(renames, &elem(&1, 0))}
    end
  end

  defp collect_column_rename(%{rename_from: old_name} = column, renames, previous_names)
       when is_atom(old_name) and not is_nil(old_name) and old_name != column.name do
    cond do
      MapSet.member?(previous_names, old_name) ->
        {:cont, [{old_name, column.name} | renames]}

      MapSet.member?(previous_names, column.name) ->
        {:cont, renames}

      true ->
        {:halt, {:error, {:rename_source_missing, old_name, column.name}}}
    end
  end

  defp collect_column_rename(_column, renames, _previous_names), do: {:cont, renames}

  defp build_diff(current, previous, rename_columns, matched_previous_names) do
    current_by_name = Map.new(current.columns, &{&1.name, &1})
    previous_by_name = Map.new(previous.columns, &{&1.name, &1})
    renamed_current_names = MapSet.new(rename_columns, &elem(&1, 1))

    add_columns =
      Enum.reject(current.columns, fn column ->
        Map.has_key?(previous_by_name, column.name) or MapSet.member?(renamed_current_names, column.name)
      end)

    remove_columns =
      Enum.reject(previous.columns, fn column ->
        Map.has_key?(current_by_name, column.name) or MapSet.member?(matched_previous_names, column.name)
      end)

    same_name_changes = same_name_changes(current.columns, previous_by_name)
    renamed_changes = renamed_changes(rename_columns, current_by_name, previous_by_name)
    {add_indexes, remove_indexes} = compare_named(current.indexes, previous.indexes)

    {add_auxiliary_tables, remove_auxiliary_tables} =
      compare_named(current.auxiliary_tables, previous.auxiliary_tables)

    %__MODULE__{
      add_columns: add_columns,
      remove_columns: remove_columns,
      change_columns: same_name_changes ++ renamed_changes,
      rename_columns: rename_columns,
      add_indexes: add_indexes,
      remove_indexes: remove_indexes,
      add_auxiliary_tables: add_auxiliary_tables,
      remove_auxiliary_tables: remove_auxiliary_tables,
      timestamps: compare_timestamps(current.timestamps, previous.timestamps)
    }
  end

  defp same_name_changes(current_columns, previous_by_name) do
    Enum.flat_map(current_columns, fn current_column ->
      case Map.get(previous_by_name, current_column.name) do
        nil -> []
        previous_column -> maybe_changed(previous_column, current_column)
      end
    end)
  end

  defp renamed_changes(rename_columns, current_by_name, previous_by_name) do
    Enum.flat_map(rename_columns, fn {old_name, new_name} ->
      previous_column = Map.fetch!(previous_by_name, old_name)
      current_column = Map.fetch!(current_by_name, new_name)
      comparable_previous = %{previous_column | name: new_name}
      maybe_changed(comparable_previous, current_column)
    end)
  end

  defp maybe_changed(previous, current) do
    if Schema.same_column?(previous, current), do: [], else: [{previous, current}]
  end

  defp compare_named(current, previous) do
    current_by_name = Map.new(current, &{&1.name, &1})
    previous_by_name = Map.new(previous, &{&1.name, &1})

    additions =
      Enum.filter(current, fn entry ->
        case Map.get(previous_by_name, entry.name) do
          nil -> true
          previous_entry -> previous_entry != entry
        end
      end)

    removals =
      Enum.filter(previous, fn entry ->
        case Map.get(current_by_name, entry.name) do
          nil -> true
          current_entry -> current_entry != entry
        end
      end)

    {additions, removals}
  end

  defp compare_timestamps(true, false), do: :add
  defp compare_timestamps(false, true), do: :remove
  defp compare_timestamps(_, _), do: :unchanged
end

defmodule Brando.Blueprint.Migrations.Renderer do
  @moduledoc false

  alias Brando.Blueprint.Migrations.Diff

  @doc """
  Renders an explicit reversible Ecto migration from a normalized schema diff.
  """
  @spec render(module(), String.t(), Diff.t(), map(), map() | nil) :: String.t()
  def render(module, sequence, %Diff{create?: true}, current, _previous) do
    migration_module = migration_module(module, sequence)

    """
    defmodule #{migration_module} do
      use Ecto.Migration

      def up do
        #{create_primary_table(current)}

        #{render_indexes(:create, current.indexes)}

        #{render_auxiliary_tables(:create, current.auxiliary_tables)}
      end

      def down do
        #{render_auxiliary_tables(:drop, Enum.reverse(current.auxiliary_tables))}

        drop table(#{table_atom(current.table)})
      end
    end
    """
  end

  def render(module, sequence, %Diff{} = diff, current, previous) do
    migration_module = migration_module(module, sequence)
    destructive_comment = destructive_comment(diff)

    """
    defmodule #{migration_module} do
      use Ecto.Migration

      #{destructive_comment}
      def up do
        #{render_auxiliary_tables(:drop, Enum.reverse(diff.remove_auxiliary_tables))}

        #{render_indexes(:drop, diff.remove_indexes)}

        #{render_changed_reference_constraints(:up, current.table, diff.change_columns)}

        #{render_renames(:up, current.table, diff.rename_columns)}

        #{render_alter(:up, current.table, diff)}

        #{render_indexes(:create, diff.add_indexes)}

        #{render_auxiliary_tables(:create, diff.add_auxiliary_tables)}
      end

      def down do
        #{render_auxiliary_tables(:drop, Enum.reverse(diff.add_auxiliary_tables))}

        #{render_indexes(:drop, diff.add_indexes)}

        #{render_changed_reference_constraints(:down, current.table, diff.change_columns)}

        #{render_alter(:down, current.table, diff)}

        #{render_renames(:down, current.table, diff.rename_columns)}

        #{render_indexes(:create, diff.remove_indexes)}

        #{render_auxiliary_tables(:create, diff.remove_auxiliary_tables)}
      end
    end
    """
    |> ensure_previous_schema!(previous)
  end

  defp create_primary_table(schema) do
    table = table_atom(schema.table)

    {table_opts, primary_key_line} =
      case schema.primary_key do
        false ->
          {", primary_key: false", nil}

        %{name: :id, type: :id} ->
          {"", nil}

        %{name: name, type: :id} ->
          {", primary_key: false", "add #{inspect(name)}, :bigserial, primary_key: true"}

        %{name: name, type: :uuid} ->
          {", primary_key: false", "add #{inspect(name)}, :uuid, primary_key: true"}
      end

    lines =
      [primary_key_line] ++
        Enum.map(schema.columns, &render_column(:add, &1)) ++
        if(schema.timestamps, do: ["timestamps()"], else: [])

    """
    create table(#{table}#{table_opts}) do
      #{join_lines(lines)}
    end
    """
  end

  defp render_alter(direction, table, diff) do
    lines = alter_lines(direction, diff)

    if lines == [] do
      ""
    else
      """
      alter table(#{table_atom(table)}) do
        #{join_lines(lines)}
      end
      """
    end
  end

  defp alter_lines(:up, diff) do
    Enum.map(diff.add_columns, &render_column(:add, &1)) ++
      Enum.map(diff.change_columns, fn {_old, new} -> render_column(:modify, new) end) ++
      Enum.map(diff.remove_columns, &"remove #{inspect(&1.name)}") ++
      timestamp_lines(:up, diff.timestamps)
  end

  defp alter_lines(:down, diff) do
    Enum.map(diff.add_columns, &"remove #{inspect(&1.name)}") ++
      Enum.map(diff.change_columns, fn {old, _new} -> render_column(:modify, old) end) ++
      Enum.map(diff.remove_columns, &render_column(:add, &1)) ++
      timestamp_lines(:down, diff.timestamps)
  end

  defp timestamp_lines(:up, :add), do: ["timestamps()"]
  defp timestamp_lines(:up, :remove), do: ["remove :inserted_at", "remove :updated_at"]
  defp timestamp_lines(:down, :add), do: ["remove :inserted_at", "remove :updated_at"]
  defp timestamp_lines(:down, :remove), do: ["timestamps()"]
  defp timestamp_lines(_, :unchanged), do: []

  defp render_column(operation, %{reference: nil} = column) do
    "#{operation} #{inspect(column.name)}, #{inspect(column.type)}#{render_opts(column.opts)}"
  end

  defp render_column(operation, %{reference: reference} = column) do
    "#{operation} #{inspect(column.name)}, #{render_reference(reference)}#{render_opts(column.opts)}"
  end

  defp render_reference(reference) do
    opts =
      []
      |> maybe_put_opt(:column, reference.column, reference.column != :id)
      |> maybe_put_opt(:on_delete, reference.on_delete, !is_nil(reference.on_delete))
      |> maybe_put_opt(:type, reference.type, reference.type not in [nil, :id])
      |> maybe_put_opt(:name, reference.name, !is_nil(reference.name))

    "references(#{table_atom(reference.table)}#{render_keyword_args(opts)})"
  end

  defp render_indexes(_operation, []), do: ""

  defp render_indexes(:create, indexes) do
    Enum.map_join(indexes, "\n", fn index ->
      index_fun = if index.unique, do: "unique_index", else: "index"

      "create #{index_fun}(#{table_atom(index.table)}, #{inspect(index.fields)}, name: #{inspect(index.name)})"
    end)
  end

  defp render_indexes(:drop, indexes) do
    Enum.map_join(indexes, "\n", fn index ->
      "drop index(#{table_atom(index.table)}, #{inspect(index.fields)}, name: #{inspect(index.name)})"
    end)
  end

  defp render_auxiliary_tables(_operation, []), do: ""

  defp render_auxiliary_tables(:create, tables) do
    Enum.map_join(tables, "\n", fn table ->
      column_lines = Enum.map(table.columns, &render_column(:add, &1))
      timestamp_lines = if table.timestamps, do: ["timestamps()"], else: []

      """
      create table(#{table_atom(table.name)}) do
        #{join_lines(column_lines ++ timestamp_lines)}
      end

      #{render_indexes(:create, table.indexes)}
      """
    end)
  end

  defp render_auxiliary_tables(:drop, tables) do
    Enum.map_join(tables, "\n", &"drop table(#{table_atom(&1.name)})")
  end

  defp render_changed_reference_constraints(_direction, _table, []), do: ""

  defp render_changed_reference_constraints(direction, table, changes) do
    changes
    |> Enum.flat_map(fn {old, new} ->
      reference = if direction == :up, do: old.reference, else: new.reference

      case reference do
        %{name: name} -> ["drop constraint(#{table_atom(table)}, #{inspect(name)})"]
        _ -> []
      end
    end)
    |> Enum.uniq()
    |> Enum.join("\n")
  end

  defp render_renames(_direction, _table, []), do: ""

  defp render_renames(:up, table, renames) do
    Enum.map_join(renames, "\n", fn {old_name, new_name} ->
      "rename table(#{table_atom(table)}), #{inspect(old_name)}, to: #{inspect(new_name)}"
    end)
  end

  defp render_renames(:down, table, renames) do
    Enum.map_join(Enum.reverse(renames), "\n", fn {old_name, new_name} ->
      "rename table(#{table_atom(table)}), #{inspect(new_name)}, to: #{inspect(old_name)}"
    end)
  end

  defp destructive_comment(diff) do
    case Diff.destructive_operations(diff) do
      [] -> ""
      operations -> "# Destructive operations — review before running: #{inspect(operations)}"
    end
  end

  defp migration_module(module, sequence) do
    naming = module.__naming__()
    "#{naming.application}.Migrations.#{naming.domain}.#{naming.schema}.Blueprint#{sequence}"
  end

  defp table_atom(table), do: inspect(String.to_atom(table))

  defp render_opts(opts) when map_size(opts) == 0, do: ""

  defp render_opts(opts) do
    opts
    |> Enum.sort_by(&elem(&1, 0))
    |> then(&", #{inspect(&1)}")
  end

  defp render_keyword_args([]), do: ""
  defp render_keyword_args(opts), do: ", " <> (opts |> Enum.reverse() |> inspect())

  defp maybe_put_opt(opts, _key, _value, false), do: opts
  defp maybe_put_opt(opts, key, value, true), do: [{key, value} | opts]

  defp join_lines(lines) do
    lines
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join("\n")
  end

  defp ensure_previous_schema!(_content, nil) do
    raise ArgumentError, "alter migration requires a previous Blueprint schema"
  end

  defp ensure_previous_schema!(content, _previous), do: content
end

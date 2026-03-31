defmodule Brando.Repo.Migrations.RenameModuleVarsNameToKey do
  use Ecto.Migration
  import Ecto.Query

  def up do
    query = from(m in "pages_modules", select: %{id: m.id, vars: m.vars})
    modules = Brando.repo().all(query)

    for module <- modules do
      # convert from string map to list of objects
      vars =
        module.vars
        |> Enum.map(fn
          var ->
            var
            |> Map.put("key", var["name"])
            |> Map.delete("name")
        end)

      query =
        from(m in "pages_modules",
          where: m.id == ^module.id,
          update: [set: [vars: ^vars]]
        )

      Brando.repo().update_all(query, [])
    end

    for {table, data_field} <- list_villain_columns() do
      query =
        from(m in table,
          select: %{id: m.id, data: field(m, ^data_field)},
          where: not is_nil(field(m, ^data_field)),
          order_by: [desc: m.id]
        )

      entries = Brando.repo().all(query)

      for entry <- entries do
        new_data = find_and_replace_vars(entry.data)
        update_args = Keyword.new([{data_field, new_data}])

        query =
          from(m in table,
            where: m.id == ^entry.id,
            update: [set: ^update_args]
          )

        Brando.repo().update_all(query, [])
      end
    end
  end

  def down do
  end

  def find_and_replace_vars(list) when is_list(list) do
    list
    |> Enum.reduce([], fn item, acc ->
      [find_and_replace_vars(item) | acc]
    end)
    |> Enum.reverse()
  end

  def find_and_replace_vars(map) when is_map(map) do
    map
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      processed_value =
        case key do
          "vars" ->
            Enum.map(value, fn var ->
              var
              |> Map.put("key", var["name"])
              |> Map.delete("name")
            end)

          _ ->
            case value do
              list when is_list(list) ->
                Enum.map(list, &find_and_replace_vars/1)

              m when is_map(m) ->
                find_and_replace_vars(m)

              _ ->
                value
            end
        end

      Map.put_new(acc, key, processed_value)
    end)
  end

  def find_and_replace_vars(value), do: value

  defp list_villain_columns do
    Brando.repo().all(
      from("columns",
        prefix: "information_schema",
        select: [:table_name, :column_name],
        where: [table_schema: "public"],
        where: [data_type: "jsonb"]
      )
    )
    |> Enum.filter(&String.ends_with?(&1.column_name, "data"))
    |> Enum.reject(&(&1.table_name in ~w(revisions content_modules sites_globals pages_properties)))
    |> Enum.map(fn row -> {row.table_name, String.to_existing_atom(row.column_name)} end)
  end
end

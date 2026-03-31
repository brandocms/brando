defmodule Brando.Repo.Migrations.MoveMultiRefsAndVarsUnderData do
  use Ecto.Migration
  import Ecto.Query

  def up do
    for {table, data_field} <- list_villain_columns() do
      query =
        from(m in table,
          select: %{id: m.id, data: field(m, ^data_field)},
          where: not is_nil(field(m, ^data_field)),
          order_by: [desc: m.id]
        )

      entries = Brando.repo().all(query)

      for entry <- entries do
        new_data = replace_block(entry.data)
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

  def replace_block(list) when is_list(list) do
    list
    |> Enum.reduce([], fn
      %{"type" => "module", "data" => %{"multi" => true, "entries" => entries}} = module, acc ->
        updated_entries =
          Enum.map(entries, fn
            %{"data" => _} = entry_with_data ->
              entry_with_data

            entry ->
              %{
                "uid" => entry["module_id"],
                "type" => "module_entry",
                "data" => %{"refs" => entry["refs"], "vars" => entry["vars"]}
              }
          end)

        [put_in(module, ["data", "entries"], updated_entries) | acc]

      block, acc ->
        [block | acc]
    end)
    |> Enum.reverse()
  end

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

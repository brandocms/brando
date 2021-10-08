defmodule Brando.Repo.Migrations.MoveMultiRefsAndVarsUnderData do
  use Ecto.Migration
  import Ecto.Query

  def up do
    villain_schemas = Enum.reject(Brando.Villain.list_villains(), &(elem(&1, 0) == Brando.Content.Template))
    for {schema, attrs} <- villain_schemas,
      %{name: data_field} <- attrs do
      query =
        from m in schema.__schema__(:source),
          select: %{id: m.id, data: field(m, ^data_field)},
          where: not is_nil(field(m, ^data_field)),
          order_by: [desc: m.id]

      entries = Brando.repo().all(query)

      for entry <- entries do
        new_data = replace_block(Map.get(entry, data_field))
        update_args = Keyword.new([{data_field, new_data}])

        query =
          from m in schema.__schema__(:source),
            where: m.id == ^entry.id,
            update: [set: ^update_args]

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
        updated_entries = Enum.map(entries, fn
          %{"data" => _} = entry_with_data -> entry_with_data

          entry ->
            %{
              "uid" => entry["module_id"],
              "type" => "module_entry",
              "data" => %{"refs" => entry["refs"], "vars" => entry["vars"]}
            }
        end)

        [put_in(module, ["data", "entries"], updated_entries)|acc]

      block, acc ->
        [block | acc]
    end)
    |> Enum.reverse
  end
end

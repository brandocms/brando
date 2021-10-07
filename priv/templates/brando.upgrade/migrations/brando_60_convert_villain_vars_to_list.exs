defmodule Brando.Repo.Migrations.ConvertVillainVarsToList do
  use Ecto.Migration
  import Ecto.Query

  def up do
    for {schema, attrs} <- Brando.Villain.list_villains,
      %{name: data_field} <- attrs do
      query =
        from m in schema.__schema__(:source),
          select: %{id: m.id, data: field(m, ^data_field)},
          where: not is_nil(field(m, ^data_field)),
          order_by: [desc: m.id]

      entries = Brando.repo().all(query)

      for entry <- entries do
        new_data = find_and_replace_vars(entry.data)
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

  def find_and_replace_vars(list) when is_list(list) do
    list
    |> Enum.reduce([], fn item, acc ->
      [find_and_replace_vars(item)|acc]
    end)
    |> Enum.reverse
  end

  def find_and_replace_vars(map) when is_map(map) do
    map
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      processed_value =
        case key do
          "vars" ->
            Enum.map(value, fn
              {k, v} ->
                Map.put(v, "name", k)
              var ->
                var
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
end

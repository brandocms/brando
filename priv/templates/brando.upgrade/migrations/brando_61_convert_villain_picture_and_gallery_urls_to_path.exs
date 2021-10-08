defmodule Brando.Repo.Migrations.ConvertVillainPictureGalleryURLToPath do
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
    require Logger
    cond do
      match?(%{"type" => "picture"}, map) ->
        case get_in(map, ["data", "url"]) do
          nil ->
            map
          url ->
            new_map = put_in(map, ["data", "path"], url)
            {_, new_map} = pop_in(new_map, ["data", "url"])
            new_map
        end

      match?(%{"type" => "gallery"}, map) ->
        images =
          for image <- get_in(map, ["data", "images"]) do
            case get_in(image, ["url"]) do
              nil ->
                image
              url ->
                new_image = put_in(image, ["path"], url)
                {_, new_image} = pop_in(new_image, ["url"])
                new_image
            end
          end

        put_in(map, ["data", "images"], images)

      true ->
        Enum.reduce(map, %{}, fn {key, value}, acc ->
          processed_value =
            case key do
              _key ->
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

  end

  def find_and_replace_vars(value), do: value
end

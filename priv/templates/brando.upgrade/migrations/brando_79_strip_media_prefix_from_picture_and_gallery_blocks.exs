defmodule Brando.Repo.Migrations.StripMediaPrefixFromPictureAndGalleryBlocks do
  use Ecto.Migration
  import Ecto.Query

  def change do
    for {table, data_field} <- list_villain_columns() do
      query =
        from(t in table,
          select: %{id: t.id, data_field: field(t, ^data_field)}
        )

      results = Brando.repo().all(query)

      for result <- results do
        processed_result = process_block(result)
        processed_data_field = processed_result.processed_data_field

        up_query =
          from(t in table,
            where: t.id == ^processed_result.id,
            update: [set: ^[{data_field, processed_data_field}]]
          )

        Brando.repo().update_all(up_query, [])
      end
    end
  end

  def process_block(%{data_field: data_field, id: id}) do
    %{id: id, processed_data_field: replace_block(data_field)}
  end

  def replace_block(nil), do: nil

  def replace_block(blocks) do
    Enum.reduce(blocks, [], fn
      %{"data" => %{"type" => "picture"} = old_block} = ref, acc ->
        case String.starts_with?(old_block["data"]["path"], "/media/") do
          true ->
            new_block = update_in(old_block, ["data", "path"], &String.replace(&1, "/media/", ""))
            old_sizes = get_in(new_block, ["data", "sizes"])

            updated_sizes =
              Enum.map(old_sizes, fn {k, v} ->
                case String.starts_with?(v, "/media/") do
                  true -> {k, String.replace(v, "/media/", "")}
                  false -> {k, v}
                end
              end)
              |> Enum.into(%{})

            new_block = put_in(new_block, ["data", "sizes"], updated_sizes)

            [%{ref | "data" => new_block} | acc]

          false ->
            [ref | acc]
        end

      %{"data" => %{"type" => "gallery"} = old_block} = ref, acc ->
        # list
        images = get_in(old_block, ["data", "images"])

        new_images =
          Enum.map(images, fn image ->
            key = (Map.has_key?(image, "url") && "url") || "path"

            case String.starts_with?(Map.get(image, key), "/media/") do
              true ->
                image = Map.put(image, "path", String.replace(Map.get(image, key), "/media/", ""))
                image = Map.delete(image, "url")
                old_sizes = image["sizes"]

                updated_sizes =
                  Enum.map(old_sizes, fn {k, v} ->
                    case String.starts_with?(v, "/media/") do
                      true -> {k, String.replace(v, "/media/", "")}
                      false -> {k, v}
                    end
                  end)
                  |> Enum.into(%{})

                Map.put(image, "sizes", updated_sizes)

              false ->
                image
            end
          end)

        new_block = put_in(old_block, ["data", "images"], new_images)
        [%{ref | "data" => new_block} | acc]

      %{"type" => "module", "data" => %{"refs" => refs}} = module, acc ->
        [
          put_in(
            module,
            [
              Access.key("data"),
              Access.key("refs")
            ],
            replace_block(refs)
          )
          | acc
        ]

      %{"type" => "container", "data" => %{"blocks" => blocks}} = container, acc ->
        [
          put_in(
            container,
            [
              Access.key("data"),
              Access.key("blocks")
            ],
            replace_block(blocks)
          )
          | acc
        ]

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
        where: fragment("data_type IN ('json', 'jsonb')")
      )
    )
    |> Enum.filter(&String.ends_with?(&1.column_name, "data"))
    |> Enum.reject(&(&1.table_name in ~w(revisions content_modules sites_globals pages_properties)))
    |> Enum.map(fn row -> {row.table_name, String.to_atom(row.column_name)} end)
  end
end

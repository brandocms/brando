defmodule Brando.Repo.Migrations.ReplaceSlideshowBlocksWithGalleryBlocks do
  use Ecto.Migration
  import Ecto.Query

  def change do
    query =
      from(m in "content_modules",
        select: %{
          id: m.id,
          refs: m.refs
        }
      )

    modules = Brando.repo().all(query)

    for module <- modules do
      new_refs = replace_block(module.refs)

      query =
        from(m in "content_modules",
          where: m.id == ^module.id,
          update: [
            set: [
              refs: ^new_refs
            ]
          ]
        )

      Brando.repo().update_all(query, [])
    end

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
      %{"type" => "slideshow"} = old_block, acc ->
        new_block = Map.put(old_block, "type", "gallery")
        new_block = put_in(new_block, ["data", "type"], "slideshow")

        [new_block | acc]

      %{"type" => "slider"} = old_block, acc ->
        new_block = Map.put(old_block, "type", "gallery")
        new_block = put_in(new_block, ["data", "type"], "slider")

        [new_block | acc]

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

      %{"data" => %{"type" => "slideshow"} = old_block} = ref, acc ->
        new_block = Map.put(old_block, "type", "gallery")
        new_block = put_in(new_block, ["data", "type"], "slideshow")

        [%{ref | "data" => new_block} | acc]

      %{"data" => %{"type" => "slider"} = old_block} = ref, acc ->
        new_block = Map.put(old_block, "type", "gallery")
        new_block = put_in(new_block, ["data", "type"], "slider")

        [%{ref | "data" => new_block} | acc]

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

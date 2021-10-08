defmodule Brando.Repo.Migrations.ReplaceSlideshowBlocksWithGalleryBlocks do
  use Ecto.Migration
  import Ecto.Query

  def change do
    query =
      from m in "content_modules",
        select: %{
          id: m.id,
          refs: m.refs
        }

    modules = Brando.repo().all(query)

    for module <- modules do
      new_refs = replace_block(module.refs)

      query =
        from(m in "content_modules",
          where: m.id == ^module.id,
          update: [set: [
            refs: ^new_refs
          ]]
        )

      Brando.repo().update_all(query, [])
    end

    villain_schemas = Enum.reject(Brando.Villain.list_villains(), &(elem(&1, 0) == Brando.Content.Template))

    for {schema, fields} <- villain_schemas do
      Enum.map(fields, fn %{name: f} ->
        query = from(t in schema.__schema__(:source),
          select: %{id: t.id, data_field: field(t, ^f)}
        )

        results = Brando.repo().all(query)
        for result <- results do
          processed_result = process_block(result)
          processed_data_field = processed_result.processed_data_field

          up_query =
            from(t in schema.__schema__(:source),
              where: t.id == ^processed_result.id,
              update: [set: ^[{f, processed_data_field}]]
            )

          Brando.repo().update_all(up_query, [])
        end
      end)
    end
  end

  def process_block(%{data_field: data_field, id: id}) do
    %{id: id, processed_data_field: replace_block(data_field)}
  end

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
end

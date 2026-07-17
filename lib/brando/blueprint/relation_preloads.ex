defmodule Brando.Blueprint.RelationPreloads do
  @moduledoc """
  Builds relation preloads for complete Blueprint entry queries.

  This read concern is separate from relation casting so changeset compilation
  does not inherit nested asset and relation-schema dependencies.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Blueprint.Assets
  alias Brando.Blueprint.Relations

  @preload_relation_types [:belongs_to, :has_many, :has_one, :many_to_many]

  @doc """
  Returns preloads for persisted relations on `schema`.

  Cast `has_many` relations include their direct assets and non-recursive
  relations. Their declared `preload_order` is preserved; sequenced children
  default to ascending sequence when no explicit order is configured.
  """
  @spec for_schema(module()) :: list()
  def for_schema(schema) do
    schema
    |> Relations.__relations__()
    |> Enum.filter(
      &(&1.type in @preload_relation_types and &1.name != :creator and
          &1.opts.module != :blocks)
    )
    |> Enum.map(&preload_relation(&1, schema))
  end

  defp preload_relation(
         %{type: :has_many, name: name, opts: %{cast: true, module: module} = opts},
         parent_schema
       ) do
    sub_preloads = asset_preloads(module) ++ relation_preloads(module, parent_schema)

    case preload_order(module, opts) do
      nil ->
        preload_unsequenced(name, sub_preloads)

      order ->
        preload_query = from entry in module, order_by: ^order, preload: ^sub_preloads
        {name, preload_query}
    end
  end

  defp preload_relation(%{name: name}, _parent_schema), do: name

  defp asset_preloads(schema), do: Enum.map(Assets.__assets__(schema), & &1.name)

  defp relation_preloads(schema, parent_schema) do
    for relation <- Relations.__relations__(schema),
        relation.opts.module != parent_schema,
        relation.type not in [:embeds_many, :embeds_one] do
      relation.name
    end
  end

  defp preload_order(module, opts) do
    Map.get(opts, :preload_order) || sequenced_order(module)
  end

  defp sequenced_order(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :has_trait, 1) and module.has_trait(:sequenced) do
      [asc: :sequence]
    end
  end

  defp preload_unsequenced(name, []), do: name
  defp preload_unsequenced(name, preloads), do: {name, preloads}
end

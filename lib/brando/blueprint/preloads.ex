defmodule Brando.Blueprint.Preloads do
  @moduledoc """
  Composes the complete preload set for a Blueprint schema.

  Asset, relation, block, alternate-entry, and identifier preloads are owned by
  their respective subsystems and combined here at the entry-query boundary.
  """

  alias Brando.Blueprint.AssetPreloads
  alias Brando.Blueprint.RelationPreloads
  alias Brando.Content.AlternateEntries
  alias Brando.Content.BlockPreloads
  alias Brando.Content.Identifier

  @doc """
  Returns every preload required to materialize a complete Blueprint entry.

  Pass `skip_blocks: true` when block relations are not needed.
  """
  @spec for_schema(module(), keyword()) :: list()
  def for_schema(schema, opts \\ []) do
    blocks_preloads =
      if Keyword.get(opts, :skip_blocks, false),
        do: [],
        else: BlockPreloads.for_schema(schema)

    Enum.uniq(
      AssetPreloads.for_schema(schema) ++
        RelationPreloads.for_schema(schema) ++
        blocks_preloads ++
        AlternateEntries.preloads_for(schema) ++
        Identifier.preloads_for(schema)
    )
  end
end

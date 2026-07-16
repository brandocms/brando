defmodule Brando.Datasource.Invalidation do
  @moduledoc """
  Invalidates rendered entries that consume a Blueprint datasource.

  Keeping this mutation boundary separate from datasource metadata prevents
  background render workers from forming a cycle with `Brando.Content.Blocks`.
  """

  alias Brando.Content.BlockReferences
  alias Brando.Content.RenderQueue
  alias Brando.Datasource.Registry

  @doc """
  Enqueues re-rendering for entries that reference `datasource_module`.

  The triggering entry is excluded when supplied, matching the mutation
  pipeline's existing behavior.
  """
  @spec update(module() | {module(), atom(), atom()}, struct() | nil) :: {:ok, struct() | nil}
  def update(datasource_module, entry \\ nil) do
    if Registry.datasource?(datasource_module) do
      datasource_module
      |> BlockReferences.list_block_ids_using_datamodule()
      |> BlockReferences.reject_blocks_belonging_to_entry(entry)
      |> RenderQueue.enqueue_map()
    end

    {:ok, entry}
  end
end

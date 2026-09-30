defmodule Brando.Content.BlockArchive do
  @moduledoc """
  A block tree the block audit removed, kept so it can be restored: the rows
  of the tree's tables as they were (`data`), and what it was for display
  (`summary`). See `Brando.Content.BlockAudit`.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "content_block_archive" do
    field :root_block_id, :integer
    field :uid, :string
    field :block_count, :integer, default: 1
    field :summary, :map, default: %{}
    field :data, :map
    field :removed_by_id, :integer

    timestamps(updated_at: false)
  end
end

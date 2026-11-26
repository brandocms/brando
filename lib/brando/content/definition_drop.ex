defmodule Brando.Content.DefinitionDrop do
  @moduledoc """
  A ref or var row a release apply dropped from a block, in
  `content_definition_drops`: the release removed its key, and the operator
  chose to drop what blocks held in it (`Brando.Content.Definition.Drops`).

    * `batch_id` - the apply's (`Brando.Content.DefinitionBatch`)
    * `module_uid`, `block_id` - the module and the block the row belonged to
    * `kind`, `key` - `"ref"` or `"var"`, and its name or key
    * `row` - the row as the database had it, every column

  A revert of the apply puts the rows back; keeping it, or the next release
  apply, deletes them. Planning and the apply's status never load them.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "content_definition_drops" do
    field :batch_id, Ecto.UUID
    field :module_uid, :string
    field :block_id, :integer
    field :kind, :string
    field :key, :string
    field :row, :map
    field :inserted_at, :utc_datetime_usec
  end
end

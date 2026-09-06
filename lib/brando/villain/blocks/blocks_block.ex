defmodule Brando.Villain.Blocks.BlocksBlock do
  @moduledoc """
  A named insertion point for an owned collection of module blocks.

  Content lives in an internal `Brando.Content.Block` slot, matched by the
  ref's name. Resetting or replacing a ref never replaces its block subtree.
  """
  use Brando.Villain.Block, type: "blocks"

  defmodule Data do
    @moduledoc false
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false
    embedded_schema do
      field :module_set, :string, default: "all"
    end

    def changeset(struct, params \\ %{}) do
      struct
      |> cast(params, [:module_set])
      |> validate_required([:module_set])
    end
  end
end

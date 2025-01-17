defmodule Brando.Villain.Blocks.TextBlock do
  @moduledoc false
  use Brando.Villain.Block,
    type: "text"

  defmodule Data do
    @moduledoc false
    use Ecto.Schema

    import Ecto.Changeset

    @primary_key false

    embedded_schema do
      field :text, :string
      field :type, Ecto.Enum, values: [:paragraph, :lede, :lead], default: :paragraph
      field :extensions, {:array, :string}
    end

    def changeset(struct, params \\ %{}) do
      cast(struct, params, ~w(text type extensions)a)
    end
  end

  def protected_attrs do
    [:text]
  end
end

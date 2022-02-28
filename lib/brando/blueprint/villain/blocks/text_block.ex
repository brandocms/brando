defmodule Brando.Blueprint.Villain.Blocks.TextBlock do
  defmodule Data do
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

  use Brando.Blueprint.Villain.Block,
    type: "text"

  def protected_attrs do
    [:text]
  end
end

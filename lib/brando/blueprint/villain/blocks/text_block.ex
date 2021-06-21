defmodule Brando.Blueprint.Villain.Blocks.TextBlock do
  defmodule Data do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key false

    embedded_schema do
      field :text, :string
      field :type, Ecto.Enum, values: [:paragraph, :lede], default: :paragraph
      field :extensions, {:array, :string}
    end

    def changeset(struct, params \\ %{}) do
      struct
      |> cast(params, ~w(text type extensions)a)
    end
  end

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :type, :string
    field :hidden, :boolean, default: false
    field :deleted, :boolean, default: false
    embeds_one :data, __MODULE__.Data
  end

  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, ~w(type hidden deleted)a)
    |> cast_embed(:data)
  end
end

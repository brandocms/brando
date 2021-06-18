defmodule Brando.Blueprint.Villain.Blocks.TextBlock do
  alias Brando.Blueprint.Villain.Blocks
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :type, :string

    embeds_one :data, Data, primary_key: false do
      field :text, :string
      field :type, :string
      field :extensions, {:array, :string}
    end
  end

  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, ~w(type)a)
    |> cast_embed(:data)
  end
end

defmodule Brando.Blueprint.Villain.Blocks.PictureBlock do
  alias Brando.Blueprint.Villain.Blocks

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :type, :string
    field :hidden, :boolean, default: false
    field :deleted, :boolean, default: false

    embeds_one :data, Brando.Images.Image
  end

  def changeset(struct, params \\ %{}) do
    cs =
      struct
      |> cast(params, ~w(type hidden deleted)a)
      |> cast_embed(:data)

    require Logger
    Logger.error(inspect(cs.data, pretty: true))

    cs
  end
end

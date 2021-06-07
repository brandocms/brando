defmodule Brando.Blueprint.Villain.Blocks.PictureBlock do
  alias Brando.Blueprint.Villain.Blocks

  use Ecto.Schema

  @primary_key false

  embedded_schema do
    field :type, :string
    field :hidden, :boolean, default: false
    field :deleted, :boolean, default: false

    embeds_one :data, Brando.Images.Image
  end
end

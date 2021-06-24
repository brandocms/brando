defmodule Brando.Blueprint.Villain.Blocks.GalleryBlock do
  alias Brando.Blueprint.Villain.Blocks

  use Ecto.Schema

  @primary_key false

  embedded_schema do
    field :uid, :string
    field :type, :string
    field :hidden, :boolean, default: false
    field :mark_for_deletion, :boolean, default: false, virtual: true

    embeds_one :data, Data, primary_key: false do
      embeds_many :images, Brando.Images.Image
      field :class, :string
      field :series_slug, :string, default: "post"
      field :lightbox, :boolean, default: false
      field :placeholder, :string, default: "dominant_color"
    end
  end
end

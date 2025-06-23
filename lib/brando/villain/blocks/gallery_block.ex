defmodule Brando.Villain.Blocks.GalleryBlock do
  @moduledoc false
  use Brando.Villain.Block,
    type: "gallery"

  defmodule Data do
    @moduledoc false
    use Brando.Blueprint,
      application: "Brando",
      domain: "Villain",
      schema: "GalleryBlockData",
      singular: "gallery_block_data",
      plural: "gallery_block_datas",
      gettext_module: Brando.Gettext

    @primary_key false
    data_layer :embedded
    identifier false
    persist_identifier false

    attributes do
      attribute :class, :string
      attribute :series_slug, :string, default: "post"
      attribute :lightbox, :boolean, default: false

      attribute :placeholder, :enum,
        values: [:svg, :dominant_color, :dominant_color_faded, :micro, :none],
        default: :dominant_color

      attribute :display, :enum,
        values: [:list, :grid],
        default: :grid

      attribute :type, :enum,
        values: [:gallery, :slider, :slideshow],
        default: :gallery

      attribute :formats, {:array, Ecto.Enum}, values: [:original, :jpg, :png, :gif, :webp, :avif, :svg]
    end
  end
end

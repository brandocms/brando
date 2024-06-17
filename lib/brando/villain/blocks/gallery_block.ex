defmodule Brando.Villain.Blocks.GalleryBlock do
  defmodule Data do
    use Brando.Blueprint,
      application: "Brando",
      domain: "Villain",
      schema: "GalleryBlockData",
      singular: "gallery_block_data",
      plural: "gallery_block_datas",
      gettext_module: Brando.Gettext

    alias Brando.Villain.Blocks

    @primary_key false
    data_layer :embedded
    identifier false

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

      attribute :formats, {:array, Ecto.Enum},
        values: [:original, :jpg, :png, :gif, :webp, :avif, :svg]
    end

    relations do
      relation :images, :embeds_many,
        module: Blocks.PictureBlock.Data,
        on_replace: :delete,
        sort_param: :sort_images
    end
  end

  use Brando.Villain.Block,
    type: "gallery"

  def protected_attrs do
    [:images]
  end
end

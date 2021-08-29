defmodule Brando.Blueprint.Villain.Blocks.GalleryBlock do
  defmodule Data do
    use Brando.Blueprint,
      application: "Brando",
      domain: "Villain",
      schema: "GalleryBlockData",
      singular: "gallery_block_data",
      plural: "gallery_block_datas",
      gettext_module: Brando.Gettext

    alias Brando.Blueprint.Villain.Blocks
    alias Brando.Images.Focal

    @primary_key false
    data_layer :embedded
    identifier "{{ entry.type }}"

    attributes do
      attribute :class, :string
      attribute :series_slug, :string, default: "post"
      attribute :lightbox, :boolean, default: false
      attribute :placeholder, :string, default: "dominant_color"
    end

    relations do
      relation :images, :embeds_many, module: Blocks.PictureBlockData
    end
  end

  use Brando.Blueprint.Villain.Block,
    type: "gallery"
end

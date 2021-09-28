defmodule Brando.Blueprint.Villain.Blocks.MediaBlock do
  defmodule Data do
    use Brando.Blueprint,
      application: "Brando",
      domain: "Villain",
      schema: "MediaBlockData",
      singular: "media_block_data",
      plural: "media_block_datas",
      gettext_module: Brando.Gettext

    alias Brando.Blueprint.Villain.Blocks

    @primary_key false
    data_layer :embedded
    identifier "{{ entry.type }}"

    attributes do
      attribute :available_blocks, {:array, :string}, default: ["picture", "video"]
    end

    relations do
      relation :template_picture, :embeds_one, module: Blocks.PictureBlock.Data
      relation :template_video, :embeds_one, module: Blocks.VideoBlock.Data
      relation :template_gallery, :embeds_one, module: Blocks.GalleryBlock.Data
      relation :template_svg, :embeds_one, module: Blocks.SvgBlock.Data
    end
  end

  use Brando.Blueprint.Villain.Block,
    type: "media"
end

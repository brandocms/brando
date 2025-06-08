defmodule Brando.Villain.Blocks.VideoBlock do
  @moduledoc false
  use Brando.Villain.Block,
    type: "video"

  defmodule Data do
    @moduledoc false
    use Brando.Blueprint,
      application: "Brando",
      domain: "Villain",
      schema: "VideoBlockData",
      singular: "video_block_data",
      plural: "video_block_datas",
      gettext_module: Brando.Gettext

    @primary_key false
    data_layer :embedded

    identifier false
    persist_identifier false

    attributes do
      # Override fields - these can override values from the referenced video
      attribute :title, :string
      attribute :poster, :string
      
      # Block-specific styling and behavior
      attribute :autoplay, :boolean, default: false
      attribute :opacity, :integer, default: 0
      attribute :preload, :boolean, default: false
      attribute :play_button, :boolean, default: false
      attribute :controls, :boolean, default: false
      attribute :cover, :string, default: "false"
      attribute :aspect_ratio, :string
    end

    relations do
      relation :cover_image, :embeds_one, module: Brando.Villain.Blocks.PictureBlock.Data
    end
  end

  def apply_ref(Brando.Villain.Blocks.MediaBlock, ref_src, ref_target) do
    # in order to not overwrite the chosen media block, we have to get the media
    # block template and merge against this instead
    tpl_src = ref_src.data.data.template_video
    new_data = Map.merge(ref_target.data.data, tpl_src)
    put_in(ref_target, [Access.key(:data), Access.key(:data)], new_data)
  end

  def apply_ref(_, ref_src, ref_target) do
    new_data = Map.merge(ref_target.data.data, ref_src.data.data)
    put_in(ref_target, [Access.key(:data), Access.key(:data)], new_data)
  end
end

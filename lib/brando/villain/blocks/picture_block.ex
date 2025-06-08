defmodule Brando.Villain.Blocks.PictureBlock do
  @moduledoc false
  use Brando.Villain.Block,
    type: "picture"

  defmodule Data do
    @moduledoc false
    use Brando.Blueprint,
      application: "Brando",
      domain: "Villain",
      schema: "PictureBlockData",
      singular: "picture_block_data",
      plural: "picture_block_datas",
      gettext_module: Brando.Gettext


    @primary_key false
    data_layer :embedded
    identifier false
    persist_identifier false

    attributes do
      # Override fields - these can override values from the referenced image
      attribute :title, :text
      attribute :credits, :text
      attribute :alt, :text
      
      # Block-specific styling and behavior
      attribute :picture_class, :text
      attribute :img_class, :text
      attribute :link, :text
      attribute :srcset, :text
      attribute :media_queries, :text
      attribute :lazyload, :boolean, default: false
      attribute :moonwalk, :boolean, default: false
      attribute :placeholder, :enum,
        values: [:svg, :dominant_color, :dominant_color_faded, :micro, :none],
        default: :dominant_color
      attribute :fetchpriority, :enum,
        values: [:high, :low, :auto],
        default: :auto
    end
  end

  def apply_ref(Brando.Villain.Blocks.MediaBlock, ref_src, ref_target) do
    # in order to not overwrite the chosen media block, we have to get the media
    # block template and merge against this instead
    tpl_src = ref_src.data.data.template_picture
    new_data = Map.merge(ref_target.data.data, tpl_src)
    put_in(ref_target, [Access.key(:data), Access.key(:data)], new_data)
  end

  def apply_ref(_, ref_src, ref_target) do
    new_data = Map.merge(ref_target.data.data, ref_src.data.data)
    put_in(ref_target, [Access.key(:data), Access.key(:data)], new_data)
  end
end

defmodule Brando.Villain.Blocks.PictureBlock do
  defmodule Data do
    use Brando.Blueprint,
      application: "Brando",
      domain: "Villain",
      schema: "PictureBlockData",
      singular: "picture_block_data",
      plural: "picture_block_datas",
      gettext_module: Brando.Gettext

    alias Brando.Images.Focal

    @primary_key false
    data_layer :embedded
    identifier false
    persist_identifier false

    attributes do
      attribute :picture_class, :text
      attribute :img_class, :text
      attribute :link, :text
      attribute :srcset, :text
      attribute :media_queries, :text

      attribute :title, :text
      attribute :credits, :text

      attribute :formats, {:array, Ecto.Enum},
        values: [:original, :jpg, :png, :gif, :webp, :avif, :svg]

      attribute :alt, :text
      attribute :path, :text
      attribute :width, :integer
      attribute :height, :integer
      attribute :sizes, :map
      attribute :cdn, :boolean, default: false
      attribute :lazyload, :boolean, default: false
      attribute :moonwalk, :boolean, default: false
      attribute :dominant_color, :text

      attribute :placeholder, :enum,
        values: [:svg, :dominant_color, :dominant_color_faded, :micro, :none],
        default: :dominant_color
    end

    relations do
      relation :focal, :embeds_one, module: Focal, on_replace: :delete
    end
  end

  use Brando.Villain.Block,
    type: "picture"

  def protected_attrs do
    [:sizes, :path, :dominant_color, :focal, :height, :width, :formats]
  end

  def apply_ref(Brando.Villain.Blocks.MediaBlock, ref_src, ref_target) do
    # in order to not overwrite the chosen media block, we have to get the media
    # block template and merge against this instead
    tpl_src = ref_src.data.data.template_picture
    protected_attrs = __MODULE__.protected_attrs()
    overwritten_attrs = Map.keys(tpl_src) -- protected_attrs
    new_attrs = Map.take(tpl_src, overwritten_attrs)
    new_data = Map.merge(ref_target.data.data, new_attrs)
    put_in(ref_target, [Access.key(:data), Access.key(:data)], new_data)
  end

  def apply_ref(_, ref_src, ref_target) do
    protected_attrs = __MODULE__.protected_attrs()
    overwritten_attrs = Map.keys(ref_src.data.data) -- protected_attrs
    new_attrs = Map.take(ref_src.data.data, overwritten_attrs)
    new_data = Map.merge(ref_target.data.data, new_attrs)
    put_in(ref_target, [Access.key(:data), Access.key(:data)], new_data)
  end
end

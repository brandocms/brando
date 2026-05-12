defmodule Brando.Villain.Blocks.PictureBlock do
  @moduledoc false
  use Brando.Villain.Block, type: "picture"

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

      attribute :formats, {:array, Ecto.Enum}, values: [:original, :jpg, :png, :gif, :webp, :avif, :svg]
      attribute :config_target, :text
    end
  end

  def apply_ref(Brando.Villain.Blocks.MediaBlock, ref_src, ref_target_changeset) do
    Brando.Villain.Block.merge_ref_template(:template_picture, ref_src, ref_target_changeset, protected_attrs())
  end

  def apply_ref(_src_type, ref_src, ref_target_changeset) do
    Brando.Villain.Block.merge_ref(ref_src, ref_target_changeset, protected_attrs())
  end
end

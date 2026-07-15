defmodule Brando.Villain.Blocks.GalleryBlock do
  @moduledoc false
  use Brando.Villain.Block, type: "gallery"

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
      attribute :lightbox, :boolean, default: false
      attribute :image_config_target, :string
      attribute :video_config_target, :string

      attribute :allowed_types, {:array, Ecto.Enum},
        values: [:image, :video],
        default: [:image, :video]

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

    relations do
      relation :gallery_object_overrides, :embeds_many, module: Brando.Villain.Blocks.GalleryObjectOverride
    end
  end

  def apply_ref(Brando.Villain.Blocks.MediaBlock, ref_src, ref_target_changeset) do
    Brando.Villain.Block.merge_ref_template(:template_gallery, ref_src, ref_target_changeset, protected_attrs())
  end

  def apply_ref(_src_type, ref_src, ref_target_changeset) do
    Brando.Villain.Block.merge_ref(ref_src, ref_target_changeset, protected_attrs())
  end
end

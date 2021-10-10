defmodule Brando.Blueprint.Villain.Blocks.PictureBlock do
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
    identifier "{{ entry.type }}"

    attributes do
      attribute :picture_class, :text
      attribute :img_class, :text
      attribute :link, :text
      attribute :srcset, :text
      attribute :media_queries, :text

      attribute :title, :text
      attribute :credits, :text
      attribute :formats, {:array, Ecto.Enum}, values: [:original, :jpg, :png, :gif, :webp, :avif]
      attribute :alt, :text
      attribute :path, :text
      attribute :width, :integer
      attribute :height, :integer
      attribute :sizes, :map
      attribute :cdn, :boolean, default: false
      attribute :dominant_color, :text

      attribute :placeholder, :enum,
        values: [:svg, :dominant_color, :micro, :none],
        default: :dominant_color
    end

    relations do
      relation :focal, :embeds_one, module: Focal
    end
  end

  use Brando.Blueprint.Villain.Block,
    type: "picture"
end

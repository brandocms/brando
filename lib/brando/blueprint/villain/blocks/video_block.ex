defmodule Brando.Blueprint.Villain.Blocks.VideoBlock do
  defmodule Data do
    use Brando.Blueprint,
      application: "Brando",
      domain: "Villain",
      schema: "VideoBlockData",
      singular: "video_block_data",
      plural: "video_block_datas",
      gettext_module: Brando.Gettext

    @primary_key false
    data_layer :embedded
    identifier "{{ entry.type }}"

    attributes do
      attribute :url, :string
      attribute :source, :enum, values: [:youtube, :vimeo, :file]
      attribute :remote_id, :string
      attribute :poster, :string
      attribute :width, :integer
      attribute :height, :integer
      attribute :autoplay, :boolean, default: false
      attribute :opacity, :integer, default: 0
      attribute :preload, :boolean, default: false
      attribute :play_button, :boolean, default: false
      attribute :controls, :boolean, default: false
      attribute :cover, :string, default: "false"
      attribute :thumbnail_url, :string
      attribute :title, :string
    end

    relations do
      relation :cover_image, :embeds_one, module: Brando.Blueprint.Villain.Blocks.PictureBlock.Data
    end
  end

  use Brando.Blueprint.Villain.Block,
    type: "video"

  def protected_attrs do
    [:url, :source, :remote_id, :width, :height, :thumbnail_url]
  end

  def apply_ref(Brando.Blueprint.Villain.Blocks.MediaBlock, ref_src, ref_target) do
    # in order to not overwrite the chosen media block, we have to get the media
    # block template and merge against this instead
    tpl_src = ref_src.data.data.template_video
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

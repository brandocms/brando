defmodule Brando.Villain.Blocks.VideoBlock do
  @moduledoc false
  use Brando.Villain.Block, type: "video"

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
      # Playback override fields — nil = use video's value
      attribute :autoplay, :boolean
      attribute :preload, :boolean
      attribute :controls, :boolean
      attribute :loop, :boolean
      attribute :muted, :boolean

      # Block-specific styling and behavior (not overrides, keep defaults)
      attribute :opacity, :integer, default: 0
      attribute :play_button, :boolean, default: false
      attribute :progress, :boolean, default: false
      attribute :cover, :string, default: "false"
      attribute :aspect_ratio, :string
      attribute :video_class, :string
      attribute :container_class, :string
      attribute :config_target, :text
    end

    relations do
      relation :cover_image, :embeds_one, module: Brando.Villain.Blocks.PictureBlock.Data
    end
  end

  def apply_ref(Brando.Villain.Blocks.MediaBlock, ref_src, ref_target_changeset) do
    Brando.Villain.Block.merge_ref_template(:template_video, ref_src, ref_target_changeset, protected_attrs())
  end

  def apply_ref(_src_type, ref_src, ref_target_changeset) do
    Brando.Villain.Block.merge_ref(ref_src, ref_target_changeset, protected_attrs())
  end
end

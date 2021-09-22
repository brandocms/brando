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
      attribute :cover, :string, default: "false"
      attribute :thumbnail_url, :string
      attribute :title, :string
    end
  end

  use Brando.Blueprint.Villain.Block,
    type: "video"
end

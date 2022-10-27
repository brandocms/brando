defmodule Brando.Videos.Video do
  @moduledoc """
  Video
  """
  use Brando.Blueprint,
    application: "Brando",
    domain: "Videos",
    schema: "Video",
    singular: "video",
    plural: "videos",
    gettext_module: Brando.Gettext

  attributes do
    attribute :url, :text
    attribute :source, :enum, values: [:youtube, :vimeo, :file, :remote_file]
    attribute :filename, :text
    attribute :remote_id, :text
    attribute :width, :integer
    attribute :height, :integer
    attribute :thumbnail_url, :text

    attribute :autoplay, :boolean
    attribute :preload, :boolean
    attribute :loop, :boolean
  end

  # relations do
  #   relation :focal, :embeds_one, module: Focal
  # end

  @derive {Jason.Encoder,
           only: [
             :url,
             :filename,
             :source,
             :remote_id,
             :width,
             :height,
             :thumbnail_url
           ]}
end

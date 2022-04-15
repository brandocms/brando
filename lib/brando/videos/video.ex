defmodule Brando.Videos.Video do
  @moduledoc """
  Embedded video
  """
  use Brando.Blueprint,
    application: "Brando",
    domain: "Videos",
    schema: "Video",
    singular: "video",
    plural: "videos",
    gettext_module: Brando.Gettext

  attributes do
    attribute :url, :text, required: true
    attribute :source, :enum, values: [:youtube, :vimeo, :file]
    attribute :filename, :text
    attribute :remote_id, :text
    attribute :width, :integer
    attribute :height, :integer
    attribute :thumbnail_url, :text
  end

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

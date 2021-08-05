defmodule Brando.Images.Image do
  @moduledoc """
  Embedded image
  """
  use Brando.Blueprint,
    application: "Brando",
    domain: "Images",
    schema: "Image",
    singular: "image",
    plural: "images",
    gettext_module: Brando.Gettext

  alias Brando.Images.Focal

  data_layer :embedded
  @primary_key false

  attributes do
    attribute :title, :text
    attribute :credits, :text
    attribute :alt, :text
    attribute :path, :text, required: true
    attribute :width, :integer
    attribute :height, :integer
    attribute :sizes, :map
    attribute :cdn, :boolean, default: false
    attribute :webp, :boolean, default: false
    attribute :dominant_color, :text
  end

  relations do
    # , on_replace: :delete
    relation :focal, :embeds_one, module: Focal
  end

  @derive {Jason.Encoder,
           only: [
             :title,
             :credits,
             :alt,
             :focal,
             :path,
             :sizes,
             :width,
             :height,
             :cdn,
             :webp,
             :dominant_color
           ]}
end

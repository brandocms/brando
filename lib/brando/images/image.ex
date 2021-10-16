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

  attributes do
    attribute :title, :text
    attribute :credits, :text
    attribute :alt, :text
    attribute :formats, {:array, Ecto.Enum}, values: [:original, :jpg, :png, :gif, :webp, :avif]
    attribute :path, :text, required: true
    attribute :width, :integer
    attribute :height, :integer
    attribute :sizes, :map
    attribute :cdn, :boolean, default: false
    attribute :dominant_color, :text
    attribute :config_target, :text
  end

  relations do
    relation :focal, :embeds_one, module: Focal
  end

  @derive {Jason.Encoder,
           only: [
             :title,
             :credits,
             :formats,
             :alt,
             :focal,
             :path,
             :sizes,
             :width,
             :height,
             :cdn,
             :dominant_color,
             :config_target
           ]}
end

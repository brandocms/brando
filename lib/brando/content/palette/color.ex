defmodule Brando.Content.Palette.Color do
  @moduledoc """
  Blueprint for color

  Colors are embedded by palettes
  """

  use Brando.Blueprint,
    application: "Brando",
    domain: "Content",
    schema: "Color",
    singular: "color",
    plural: "colors",
    gettext_module: Brando.Gettext

  @type t :: %__MODULE__{}

  @primary_key false
  data_layer :embedded

  identifier false
  persist_identifier false

  attributes do
    attribute :name, :string, required: true
    # A CSS custom property name (`--bg`), as the palette's key
    attribute :key, :string, required: true, constraints: [format: ~r/\A[\p{L}\p{N}_-]+\z/u]
    attribute :hex_value, :string, required: true
    attribute :instructions, :text
  end
end

defmodule Brando.Content.Palette.Color do
  @moduledoc """
  Blueprint for color

  Colors are embedded by palettes
  """

  @type t :: %__MODULE__{}

  use Brando.Blueprint,
    application: "Brando",
    domain: "Content",
    schema: "Color",
    singular: "color",
    plural: "colors",
    gettext_module: Brando.Gettext

  @primary_key false
  data_layer :embedded
  identifier "{{ entry.name }}"

  attributes do
    attribute :name, :string, required: true
    attribute :key, :string, required: true
    attribute :hex_value, :string, required: true
    attribute :instructions, :text
  end
end

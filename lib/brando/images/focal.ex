defmodule Brando.Images.Focal do
  use Brando.Blueprint,
    application: "Brando",
    domain: "Images",
    schema: "Focal",
    singular: "focal",
    plural: "focals"

  @primary_key false
  data_layer :embedded

  attributes do
    attribute :x, :integer, required: true, default: 50
    attribute :y, :integer, required: true, default: 50
  end

  @derive {Jason.Encoder, only: [:x, :y]}
end

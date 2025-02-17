defmodule Brando.Images.Focal do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "Images",
    schema: "Focal",
    singular: "focal",
    plural: "focals",
    gettext_module: Brando.Gettext

  data_layer :embedded

  @primary_key false
  @allow_mark_as_deleted false

  attributes do
    attribute :x, :integer, required: true, default: 50
    attribute :y, :integer, required: true, default: 50
  end

  @derive {Jason.Encoder, only: [:x, :y]}
end

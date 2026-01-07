defmodule Brando.Villain.Blocks.GalleryObjectOverride do
  @moduledoc false
  use Brando.Blueprint,
    application: "Brando",
    domain: "Villain",
    schema: "GalleryObjectOverride",
    singular: "gallery_object_override",
    plural: "gallery_object_overrides",
    gettext_module: Brando.Gettext

  @primary_key false
  data_layer :embedded
  identifier false
  persist_identifier false

  attributes do
    attribute :object_id, :string, required: true
    attribute :object_type, :enum, values: [:image, :video], required: true
    attribute :title, :string
    attribute :credits, :string
    attribute :alt, :string
    attribute :use_default_title, :boolean, default: true
    attribute :use_default_credits, :boolean, default: true
    attribute :use_default_alt, :boolean, default: true
  end
end

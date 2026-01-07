defmodule Brando.Content.Ref do
  @moduledoc """
  Ecto schema for a ref (used by both modules and blocks)
  """
  use Brando.Blueprint,
    application: "Brando",
    domain: "Content",
    schema: "Ref",
    singular: "ref",
    plural: "refs",
    gettext_module: Brando.Gettext

  alias Brando.Villain.Blocks

  @type t :: %__MODULE__{}

  trait Brando.Trait.CastPolymorphicEmbeds
  trait Brando.Trait.Timestamped
  trait Brando.Trait.EnsureUID

  identifier false
  persist_identifier false

  attributes do
    attribute :name, :text, required: true
    attribute :description, :text
    attribute :sequence, :integer
    attribute :uid, :string, required: true
    attribute :active, :boolean, default: true
    attribute :collapsed, :boolean, default: false

    attribute :data, PolymorphicEmbed,
      types: Blocks.list_blocks(),
      type_field_name: :type,
      on_type_not_found: :raise,
      on_replace: :update
  end

  relations do
    relation :module, :belongs_to, module: Brando.Content.Module
    relation :block, :belongs_to, module: Brando.Content.Block
    relation :gallery, :belongs_to, module: Brando.Galleries.Gallery, on_replace: :nilify
    relation :video, :belongs_to, module: Brando.Videos.Video, on_replace: :nilify
    relation :file, :belongs_to, module: Brando.Files.File, on_replace: :nilify
    relation :image, :belongs_to, module: Brando.Images.Image, on_replace: :nilify
  end

  @doc """
  Returns the standard preload list for refs with all media associations
  """
  def preloads do
    [:image, :file, video: [:thumbnail], gallery: [gallery_objects: [:image, :video]]]
  end
end

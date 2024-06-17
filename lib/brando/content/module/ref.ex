defmodule Brando.Content.Module.Ref do
  @moduledoc """
  Ecto schema for a module ref
  """
  alias Brando.Villain.Blocks

  @type t :: %__MODULE__{}

  use Brando.Blueprint,
    application: "Brando",
    domain: "Villain",
    schema: "Ref",
    singular: "ref",
    plural: "refs",
    gettext_module: Brando.Gettext

  @primary_key false
  data_layer :embedded
  trait Brando.Trait.CastPolymorphicEmbeds

  identifier false

  attributes do
    attribute :name, :text, required: true
    attribute :description, :text

    attribute :data, PolymorphicEmbed,
      types: Blocks.list_blocks(),
      type_field: :type,
      on_type_not_found: :raise,
      on_replace: :update
  end
end

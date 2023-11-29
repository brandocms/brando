defmodule Brando.Blocks.Block do
  @moduledoc """
  Blueprint for the Block schema.
  """

  @type t :: %__MODULE__{}

  use Brando.Blueprint,
    application: "Brando",
    domain: "Blocks",
    schema: "Block",
    singular: "block",
    plural: "blocks",
    gettext_module: Brando.Gettext

  import Brando.Gettext

  # ++ Traits
  trait Brando.Trait.Creator
  trait Brando.Trait.Revisioned
  # trait Brando.Trait.Sequenced, append: true
  trait Brando.Trait.Timestamped
  # --

  attributes do
    attribute :uid, :string, required: true
    attribute :type, :enum, values: [:module, :container]
    attribute :hidden, :boolean, default: false
    attribute :collapsed, :boolean, default: false
    attribute :description, :string

    # attribute :vars, {:array, Brando.PolymorphicEmbed},
    #   types: Var.types(),
    #   type_field: :type,
    #   on_type_not_found: :raise,
    #   on_replace: :delete
  end

  relations do
    relation :module, :belongs_to, module: Brando.Content.Module
    relation :parent, :belongs_to, module: __MODULE__
    relation :children, :has_many, module: __MODULE__, foreign_key: :parent_id
    relation :vars, :has_many, module: Var
    relation :refs, :embeds_many, module: __MODULE__.Ref, on_replace: :delete
  end

  absolute_url ""

  translations do
    context :naming do
      translate :singular, t("block")
      translate :plural, t("blocks")
    end
  end

  factory %{}
end

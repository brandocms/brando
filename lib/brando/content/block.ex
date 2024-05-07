defmodule Brando.Content.Block do
  @moduledoc """
  Blueprint for the Block schema.
  """

  @type t :: %__MODULE__{}

  use Brando.Blueprint,
    application: "Brando",
    domain: "Content",
    schema: "Block",
    singular: "block",
    plural: "blocks",
    gettext_module: Brando.Gettext

  import Brando.Gettext
  import Ecto.Query

  # ++ Traits
  trait Brando.Trait.Creator
  trait Brando.Trait.Revisioned
  trait Brando.Trait.Sequenced
  trait Brando.Trait.Timestamped
  # --

  attributes do
    attribute :uid, :string, required: true
    attribute :type, :enum, values: [:module, :container, :module_entry]
    attribute :active, :boolean, default: true
    attribute :collapsed, :boolean, default: false
    attribute :description, :string
    attribute :anchor, :string
    attribute :multi, :boolean, default: false
    attribute :datasource, :boolean, default: false
    attribute :rendered_html, :string
    attribute :rendered_at, :datetime
    attribute :source, Brando.Type.Module
  end

  relations do
    relation :module, :belongs_to, module: Brando.Content.Module
    relation :parent, :belongs_to, module: __MODULE__

    relation :children, :has_many,
      module: __MODULE__,
      on_replace: :delete_if_exists,
      foreign_key: :parent_id

    relation :palette, :belongs_to, module: Brando.Content.Palette

    relation :vars, :has_many,
      module: Brando.Content.Var,
      on_replace: :delete_if_exists,
      cast: true

    relation :refs, :embeds_many,
      module: Brando.Content.Module.Ref,
      on_replace: :delete,
      cast: true

    relation :block_identifiers, :has_many,
      module: Brando.Content.BlockIdentifier,
      preload_order: [asc: :sequence],
      on_replace: :delete_if_exists,
      cast: true

    relation :identifiers, :has_many,
      module: Brando.Content.Identifier,
      through: [:block_identifiers, :identifier]
  end

  absolute_url ""

  translations do
    context :naming do
      translate :singular, t("block")
      translate :plural, t("blocks")
    end
  end

  factory %{}

  def preloads do
    children_query =
      from b in __MODULE__,
        preload: [:palette, :vars, :module, children: [:palette, :vars, :children]],
        order_by: [asc: :sequence]

    [
      block: [
        :parent,
        :module,
        :vars,
        :palette,
        children: children_query,
        block_identifiers: :identifier
      ]
    ]
  end
end

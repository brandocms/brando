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
      preload_order: [asc: :sequence],
      foreign_key: :parent_id

    relation :palette, :belongs_to, module: Brando.Content.Palette

    relation :vars, :has_many,
      module: Brando.Content.Var,
      preload_order: [asc: :sequence],
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

  def maybe_cast_recursive(changeset, true, user) do
    cast_assoc(changeset, :block, with: &recursive_block_changeset(&1, &2, user))
  end

  def maybe_cast_recursive(changeset, false, user) do
    cast_assoc(changeset, :block, with: &block_changeset(&1, &2, user))
  end

  def block_changeset(block, attrs, user) do
    block
    |> cast(attrs, [
      :active,
      :collapsed,
      :anchor,
      :description,
      :uid,
      :creator_id,
      :sequence,
      :parent_id,
      :module_id,
      :anchor,
      :multi,
      :palette_id,
      :type,
      :source
    ])
    |> cast_assoc(:vars, with: &var_changeset(&1, &2, user))
    |> cast_embed(:refs, with: &ref_changeset(&1, &2, user))
    |> cast_assoc(:block_identifiers,
      with: &block_identifier_changeset(&1, &2, &3, user),
      drop_param: :drop_block_identifier_ids,
      sort_param: :sort_block_identifier_ids
    )
  end

  def recursive_block_changeset(block, attrs, user) do
    block
    |> cast(attrs, [
      :active,
      :collapsed,
      :anchor,
      :description,
      :uid,
      :creator_id,
      :sequence,
      :parent_id,
      :module_id,
      :anchor,
      :multi,
      :palette_id,
      :type,
      :source
    ])
    |> cast_assoc(:vars, with: &var_changeset(&1, &2, user))
    |> cast_embed(:refs, with: &ref_changeset(&1, &2, user))
    |> cast_assoc(:children, with: &recursive_block_changeset(&1, &2, user))
    |> cast_assoc(:block_identifiers,
      with: &block_identifier_changeset(&1, &2, &3, user),
      drop_param: :drop_block_identifier_ids,
      sort_param: :sort_block_identifier_ids
    )
  end

  def block_identifier_changeset(block_identifier, attrs, position, _user) do
    block_identifier
    |> cast(attrs, [:block_id, :identifier_id])
    |> change(sequence: position)
  end

  def var_changeset(var, attrs, _user) do
    cast(var, attrs, [
      :type,
      :label,
      :placeholder,
      :key,
      :value,
      :value_boolean,
      :important,
      :instructions,
      :color_picker,
      :color_opacity,
      :sequence,
      :creator_id,
      :module_id,
      :page_id,
      :block_id,
      :palette_id,
      :image_id,
      :file_id,
      :linked_identifier_id,
      :global_set_id
    ])
    |> cast_embed(:options)
  end

  def ref_changeset(ref, attrs, user) do
    ref
    |> cast(attrs, [:name, :description])
    |> PolymorphicEmbed.cast_polymorphic_embed(:data)
  end
end

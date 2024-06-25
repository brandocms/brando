defmodule Brando.Content.Block do
  @moduledoc """
  Blueprint for the Block schema.
  """

  @type t :: %__MODULE__{}

  @block_attrs [
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
  ]

  @var_attrs [
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
    :link_text,
    :link_type,
    :link_identifier_schemas,
    :link_target_blank,
    :link_allow_custom_text,
    :sequence,
    :creator_id,
    :module_id,
    :page_id,
    :block_id,
    :palette_id,
    :image_id,
    :file_id,
    :identifier_id,
    :global_set_id,
    :table_template_id
  ]

  use Brando.Blueprint,
    application: "Brando",
    domain: "Content",
    schema: "Block",
    singular: "block",
    plural: "blocks",
    gettext_module: Brando.Gettext

  import Brando.Gettext

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

    relation :table_rows, :has_many,
      module: Brando.Content.TableRow,
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
    |> cast(attrs, @block_attrs)
    |> cast_table_rows(user)
    |> cast_block_identifiers(user)
    |> cast_assoc(:vars, with: &var_changeset(&1, &2, user))
    |> cast_embed(:refs, with: &ref_changeset(&1, &2, user))
  end

  def recursive_block_changeset(block, attrs, user) do
    block
    |> cast(attrs, @block_attrs)
    |> cast_table_rows(user)
    |> cast_block_identifiers(user)
    |> cast_assoc(:vars, with: &var_changeset(&1, &2, user))
    |> cast_embed(:refs, with: &ref_changeset(&1, &2, user))
    |> cast_assoc(:children, with: &recursive_block_changeset(&1, &2, user))
  end

  defp cast_block_identifiers(changeset, user) do
    case Map.get(changeset.params, "table_rows") do
      "" ->
        put_assoc(changeset, :block_identifiers, [])

      _ ->
        cast_assoc(changeset, :block_identifiers,
          with: &block_identifier_changeset(&1, &2, &3, user),
          drop_param: :drop_block_identifier_ids,
          sort_param: :sort_block_identifier_ids
        )
    end
  end

  defp cast_table_rows(changeset, user) do
    case get_assoc(changeset, :table_rows) do
      [] ->
        put_assoc(changeset, :table_rows, [])

      _ ->
        cast_assoc(changeset, :table_rows,
          with: &table_row_changeset(&1, &2, &3, user),
          drop_param: :drop_table_row_ids,
          sort_param: :sort_table_row_ids
        )
    end
  end

  def table_row_changeset(table_row, attrs, position, user) do
    table_row
    |> cast(attrs, [:block_id])
    |> cast_assoc(:vars, with: &var_changeset(&1, &2, user))
    |> change(sequence: position)
  end

  def block_identifier_changeset(block_identifier, attrs, position, _user) do
    block_identifier
    |> cast(attrs, [:block_id, :identifier_id])
    |> change(sequence: position)
  end

  def var_changeset(var, attrs, _user) do
    var
    |> cast(attrs, @var_attrs)
    |> cast_embed(:options)
  end

  def ref_changeset(ref, attrs, _user) do
    ref
    |> cast(attrs, [:name, :description])
    |> PolymorphicEmbed.cast_polymorphic_embed(:data)
  end
end

defmodule Brando.Content.Block do
  @moduledoc """
  Blueprint for the Block schema.
  """

  use Brando.Blueprint,
    application: "Brando",
    domain: "Content",
    schema: "Block",
    singular: "block",
    plural: "blocks",
    gettext_module: Brando.Gettext

  use Gettext, backend: Brando.Gettext
  import Ecto.Query

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
    :container_id,
    :fragment_id,
    :anchor,
    :multi,
    :palette_id,
    :type,
    :source,
    :identifier_metas
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
    :width,
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

  # ++ Traits
  trait Brando.Trait.Creator
  trait Brando.Trait.Revisioned
  trait Brando.Trait.Sequenced
  trait Brando.Trait.Timestamped
  # --

  attributes do
    attribute :uid, :string, required: true
    attribute :type, :enum, values: [:module, :container, :module_entry, :fragment]
    attribute :active, :boolean, default: true
    attribute :collapsed, :boolean, default: false
    attribute :description, :string
    attribute :anchor, :string
    attribute :multi, :boolean, default: false
    attribute :datasource, :boolean, default: false
    attribute :rendered_html, :string
    attribute :rendered_at, :datetime
    attribute :source, Brando.Type.Module
    attribute :identifier_metas, Brando.Type.Json
  end

  relations do
    relation :container, :belongs_to, module: Brando.Content.Container
    relation :fragment, :belongs_to, module: Brando.Pages.Fragment
    relation :module, :belongs_to, module: Brando.Content.Module
    relation :palette, :belongs_to, module: Brando.Content.Palette
    relation :parent, :belongs_to, module: __MODULE__

    relation :children, :has_many,
      module: __MODULE__,
      on_replace: :delete_if_exists,
      preload_order: [asc: :sequence],
      foreign_key: :parent_id

    relation :vars, :has_many,
      module: Brando.Content.Var,
      preload_order: [asc: :sequence],
      on_replace: :delete_if_exists,
      cast: true

    relation :refs, :has_many,
      module: Brando.Content.Ref,
      preload_order: [asc: :sequence],
      on_replace: :delete_if_exists,
      cast: true

    relation :table_rows, :has_many,
      module: Brando.Content.TableRow,
      preload_order: [asc: :sequence],
      on_replace: :delete_if_exists,
      cast: true

    relation :block_identifiers, :has_many,
      module: Brando.Content.BlockIdentifier,
      preload_order: [asc: :sequence],
      on_replace: :delete_if_exists,
      cast: true

    relation :identifiers, :has_many,
      module: Brando.Content.Identifier,
      through: [:block_identifiers, :identifier],
      preload_order: [asc: :sequence]
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
    changeset = block
    |> cast(attrs, @block_attrs)
    |> unique_constraint(:uid)
    |> cast_table_rows(user)
    |> cast_block_identifiers(user)
    |> cast_assoc(:vars, with: &var_changeset(&1, &2, user))
    |> cast_assoc(:refs, with: &ref_changeset(&1, &2, user))

    # Filter out :replace changesets from refs to prevent update issues
    changeset = if is_nil(block.id) do
      changeset
      |> Ecto.Changeset.update_change(:refs, fn ref_changesets ->
        Enum.reject(ref_changesets, &(&1.action == :replace))
      end)
      |> Ecto.Changeset.update_change(:vars, fn var_changesets ->
        Enum.reject(var_changesets, &(&1.action == :replace))
      end)
      |> Map.put(:action, :insert)  # Force insert action for new blocks
    else
      changeset
    end

    changeset
  end

  def recursive_block_changeset(block, attrs, user) do
    block
    |> cast(attrs, @block_attrs)
    |> unique_constraint(:uid)
    |> cast_table_rows(user)
    |> cast_block_identifiers(user)
    |> cast_assoc(:vars, with: &var_changeset(&1, &2, user))
    |> cast_assoc(:refs, with: &ref_changeset(&1, &2, user))
    |> cast_assoc(:children, with: &recursive_block_changeset(&1, &2, user))
  end

  defp cast_block_identifiers(changeset, user) do
    case Map.get(changeset.params, "block_identifiers") do
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
    case Map.get(changeset.params, "table_rows") do
      "" ->
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
    IO.puts("=== REF_CHANGESET: Processing ref with attrs: #{inspect(Map.take(attrs, ["uid", :uid, "id", :id]))} ===")
    IO.puts("=== REF_CHANGESET: Existing ref - id: #{inspect(ref.id)}, uid: #{inspect(ref.uid)} ===")
    
    changeset = ref
    |> cast(attrs, [:name, :description, :uid, :sequence])
    |> unique_constraint(:uid)
    |> PolymorphicEmbed.cast_polymorphic_embed(:data)
    
    final_uid = Ecto.Changeset.get_field(changeset, :uid) || Ecto.Changeset.get_change(changeset, :uid)
    final_id = Ecto.Changeset.get_field(changeset, :id) || Ecto.Changeset.get_change(changeset, :id)
    action = changeset.action
    IO.puts("=== REF_CHANGESET: Final ref - id: #{inspect(final_id)}, uid: #{inspect(final_uid)}, action: #{inspect(action)} ===")
    
    # Check if this UID already exists in the database
    if final_uid do
      existing_refs = Brando.Repo.all(from r in Brando.Content.Ref, where: r.uid == ^final_uid, select: [:id, :uid, :name])
      if length(existing_refs) > 0 do
        IO.puts("=== REF_CHANGESET: DUPLICATE UID FOUND! #{final_uid} already exists in database: #{inspect(existing_refs)} ===")
        if final_id do
          IO.puts("=== REF_CHANGESET: But current ref HAS ID #{final_id}, so this should be an UPDATE, not INSERT! ===")
        else
          IO.puts("=== REF_CHANGESET: Current ref has NO ID, so Ecto will try to INSERT (causing duplicate) ===")
        end
      else
        IO.puts("=== REF_CHANGESET: UID #{final_uid} is unique in database ===")
      end
    end
    
    changeset
  end
end

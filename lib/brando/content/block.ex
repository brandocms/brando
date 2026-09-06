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

  alias Brando.Content.VarAttrs

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
    :module_origin,
    :container_id,
    :container_origin,
    :fragment_id,
    :multi,
    :palette_id,
    :palette_origin,
    :type,
    :slot_name,
    :slot_kind,
    :slot_module_set,
    :slot_remap,
    :source,
    :identifier_metas
  ]

  @var_attrs VarAttrs.all()

  # ++ Traits
  trait :creator
  trait :revisioned
  trait :sequenced
  trait :timestamped
  # --

  attributes do
    attribute :uid, :string, required: true
    attribute :type, :enum, values: [:module, :container, :module_entry, :fragment, :slot]
    attribute :slot_name, :string
    attribute :slot_kind, :enum, values: [:region, :footnote]
    attribute :slot_module_set, :string
    attribute :slot_remap, :string, virtual: true
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
    # The newest module revision whose instance-data migration was applied to this
    # block. Deliberately absent from `@block_attrs`: it is server-controlled, so
    # an entry editor opened before a module migration cannot save its way to
    # claiming it is current. See `Brando.Content.Blocks.sync_module/2`.
    attribute :module_version, :integer

    attribute :module_origin, :enum, values: [:local, :shared], default: :local
    attribute :container_origin, :enum, values: [:local, :shared], default: :local
    attribute :palette_origin, :enum, values: [:local, :shared], default: :local
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
      cast: true,
      sort_param: :sort_var_ids,
      drop_param: :drop_var_ids

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

    # `:id` breaks ties. `Brando.Trait.Sequenced` documents 0 as the default
    # sequence for a new entry, so rows sharing one are expected — the trait's
    # own fallback is `desc: :inserted_at`, which this join table has no column
    # for. Without a tiebreaker Postgres returns them in physical order, so a
    # re-save that rewrites the rows silently reorders whatever the block
    # renders from them.
    relation :block_identifiers, :has_many,
      module: Brando.Content.BlockIdentifier,
      preload_order: [asc: :sequence, asc: :id],
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
    |> validate_required(:uid)
    |> unique_constraint(:uid)
    |> cast_table_rows(user)
    |> cast_block_identifiers(user)
    |> cast_assoc(:vars,
      with: &var_changeset(&1, &2, &3, user),
      sort_param: :sort_var_ids,
      drop_param: :drop_var_ids
    )
    |> cast_assoc(:refs, with: &ref_changeset(&1, &2, user))
    |> finalize_new_block(block)
  end

  # New (nil-id) blocks: strip :replace refs/vars changesets (they cause
  # update issues on insert) and FORCE action :insert — without it, a cast
  # over a built base struct keeps Ecto's computed :update action, and the
  # repo raises NoPrimaryKeyValueError trying to update a pk-less row.
  defp finalize_new_block(changeset, block) do
    block_id =
      case block do
        %Ecto.Changeset{data: data} -> data.id
        %{id: id} -> id
        _ -> nil
      end

    if is_nil(block_id) do
      changeset
      |> Ecto.Changeset.update_change(:refs, fn ref_changesets ->
        Enum.reject(ref_changesets, &(&1.action == :replace))
      end)
      |> Ecto.Changeset.update_change(:vars, fn var_changesets ->
        Enum.reject(var_changesets, &(&1.action == :replace))
      end)
      |> Map.put(:action, :insert)
    else
      changeset
    end
  end

  def recursive_block_changeset(block, attrs, user) do
    block
    |> cast(attrs, @block_attrs)
    |> validate_required(:uid)
    |> unique_constraint(:uid)
    |> cast_table_rows(user)
    |> cast_block_identifiers(user)
    |> cast_assoc(:vars,
      with: &var_changeset(&1, &2, &3, user),
      sort_param: :sort_var_ids,
      drop_param: :drop_var_ids
    )
    |> cast_assoc(:refs, with: &ref_changeset(&1, &2, user))
    |> cast_assoc(:children, with: &recursive_block_changeset(&1, &2, user))
    |> Brando.Content.BlockSlots.validate()
    |> finalize_new_block(block)
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
    cast_assoc(changeset, :table_rows,
      with: &table_row_changeset(&1, &2, &3, user),
      drop_param: :drop_table_row_ids,
      sort_param: :sort_table_row_ids
    )
  end

  def table_row_changeset(table_row, attrs, position, user) do
    table_row
    |> cast(attrs, [:block_id])
    |> cast_assoc(:vars,
      with: &var_changeset(&1, &2, &3, user),
      sort_param: :sort_var_ids,
      drop_param: :drop_var_ids
    )
    |> change(sequence: position)
  end

  def block_identifier_changeset(block_identifier, attrs, position, _user) do
    block_identifier
    |> cast(attrs, [:block_id, :identifier_id])
    |> change(sequence: position)
  end

  @doc """
  The var fields `var_changeset/3,4` casts.

  Exposed because a var whose editing UI is not rendered has to round-trip
  these through the DOM to survive `cast_assoc/3` — see `Render.carried_var/1`.
  Driving that off this list keeps the two from drifting apart.
  """
  def var_attrs, do: @var_attrs

  @doc """
  The subset of `var_attrs/0` that `Render.carried_var/1` round-trips through
  hidden inputs for an **unsaved** var.

  Every attribute rendered there is one a user can hand-edit before submitting,
  so ownership and parentage are excluded: `creator_id` is forced server-side by
  `var_changeset/4`, and the owner FKs (`block_id`, `page_id`, `module_id`,
  `global_set_id`, `table_template_id`) are set by whichever schema's
  `cast_assoc(:vars, …)` is building the var. Carrying them from the DOM adds no
  information and lets a payload point a var at another entry's block.

  `palette_id` and `identifier_id` stay: for a palette or identifier var those
  *are* the value.
  """
  def carried_var_attrs, do: VarAttrs.carried()

  def var_changeset(var, attrs, position, user) when is_integer(position) do
    var
    |> cast(attrs, @var_attrs)
    |> put_var_creator(user)
    |> cast_embed(:options)
    |> change(sequence: position)
    |> validate_media_fks()
  end

  def var_changeset(var, attrs, user) do
    var
    |> cast(attrs, @var_attrs)
    |> put_var_creator(user)
    |> cast_embed(:options)
    |> validate_media_fks()
  end

  # `Brando.Trait.Creator` sets this on the blueprint-generated changeset, but
  # these hand-written casts never run the trait pipeline — so until now
  # `creator_id` came from the client, via the hidden inputs `carried_var/1`
  # emits for an unsaved var's whole cast surface. The user was already threaded
  # in here and simply ignored. Deriving it server-side closes creator spoofing
  # on every path at once (carried vars, block recovery, ordinary validate)
  # rather than one DOM surface at a time.
  #
  # A client-sent `creator_id` is always discarded. It is only *set* for a var
  # that does not have one yet, so an existing var keeps its original creator
  # rather than flipping to whoever edited the block last.
  defp put_var_creator(changeset, user) do
    changeset = delete_change(changeset, :creator_id)

    case {changeset.data.creator_id, user_id(user)} do
      {nil, user_id} when not is_nil(user_id) -> put_change(changeset, :creator_id, user_id)
      _ -> changeset
    end
  end

  defp user_id(%{id: id}), do: id
  defp user_id(id) when is_integer(id), do: id
  defp user_id(_), do: nil

  # These FKs are castable from params — a var's whole cast surface round-trips
  # through hidden inputs while its editing UI is unrendered (`carried_var/1`),
  # and refs carry theirs so a picker selection survives. Without a declared
  # constraint, a stale or hand-edited id raises `Ecto.ConstraintError` out of
  # the repo instead of returning an invalid changeset — which in the editor
  # means the LiveView dies and takes every unsaved change with it. That is the
  # same crash-loses-your-work failure this audit's A2 fixed.
  @media_fks [:image_id, :video_id, :file_id, :gallery_id]

  defp validate_media_fks(changeset) do
    Enum.reduce(@media_fks, changeset, fn fk, acc ->
      if fk in acc.data.__struct__.__schema__(:fields) do
        foreign_key_constraint(acc, fk)
      else
        acc
      end
    end)
  end

  def ref_changeset(ref, attrs, user) do
    ref
    |> cast(attrs, [
      :name,
      :description,
      :uid,
      :sequence,
      :active,
      :collapsed,
      # All four media FKs, matching what the picker/drawer commits through
      # `update_ref_data`. `:gallery_id` was missing, so a gallery picked on a
      # ref was dropped by the cast — the same omission as the var list above.
      # Casting the FK alongside `cast_assoc(:gallery, ...)` is safe: params
      # carry one or the other, and the relation is `on_replace: :nilify`.
      :image_id,
      :video_id,
      :file_id,
      :gallery_id
    ])
    |> unique_constraint(:uid)
    |> validate_media_fks()
    |> PolymorphicEmbed.cast_polymorphic_embed(:data)
    |> cast_assoc(:gallery, with: &Brando.Galleries.Gallery.changeset(&1, &2, user))
  end
end

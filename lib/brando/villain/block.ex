defmodule Brando.Villain.Block do
  @moduledoc """
  Use to set module as a Villain block.
  """
  @callback protected_attrs() :: [atom()]
  @callback apply_ref(module(), map(), map()) :: map()

  @doc """
  Merge ref source data into the target changeset, respecting protected attrs.

  Used by the default `apply_ref/3` — reads data from `ref_src.data.data`.
  """
  def merge_ref(ref_src, ref_target_changeset, protected_attrs) do
    merge_data(ref_src.data.data, ref_target_changeset, protected_attrs)
  end

  @doc """
  Merge template data from a specific field on the ref source into the target changeset.

  Used by blocks that need a MediaBlock-specific `apply_ref/3` clause,
  e.g. PictureBlock reads from `ref_src.data.data.template_picture`.
  """
  def merge_ref_template(template_field, ref_src, ref_target_changeset, protected_attrs) do
    tpl_src = Map.get(ref_src.data.data, template_field)
    merge_data(tpl_src, ref_target_changeset, protected_attrs)
  end

  defp merge_data(source_data, ref_target_changeset, protected_attrs) do
    import Ecto.Changeset

    current_data = get_field(ref_target_changeset, :data)

    data_changeset =
      case current_data do
        %Ecto.Changeset{} = cs -> cs
        data -> change(data)
      end

    src_attrs = Map.from_struct(source_data)
    overwritten_attrs = Map.keys(src_attrs) -- protected_attrs
    new_attrs = Map.take(src_attrs, overwritten_attrs)

    current_block_data = get_field(data_changeset, :data)
    merged_data = struct(current_block_data, new_attrs)

    current_block = apply_changes(data_changeset)
    updated_block = %{current_block | data: merged_data}

    put_change(ref_target_changeset, :data, updated_block)
  end

  defmacro __using__(opts) do
    type = Keyword.fetch!(opts, :type)

    quote generated: true do
      @behaviour Brando.Villain.Block

      use Ecto.Schema
      import Ecto.Changeset

      @primary_key false

      embedded_schema do
        field :type, :string, default: unquote(type)
        field :marked_as_deleted, :boolean, default: false, virtual: true
        embeds_one :data, __MODULE__.Data, on_replace: :update
      end

      def changeset(struct, params \\ %{}) do
        struct
        |> cast(params, ~w(type marked_as_deleted)a)
        |> cast_embed(:data)
        |> maybe_mark_for_deletion()
      end

      defp maybe_mark_for_deletion(%{changes: %{marked_as_deleted: true}} = changeset) do
        %{changeset | action: :delete}
      end

      defp maybe_mark_for_deletion(changeset), do: changeset

      def __block_type__, do: unquote(type)

      def protected_attrs, do: []
      defoverridable protected_attrs: 0

      def apply_ref(_src_type, ref_src, ref_target_changeset) do
        Brando.Villain.Block.merge_ref(ref_src, ref_target_changeset, protected_attrs())
      end

      defoverridable apply_ref: 3
    end
  end
end

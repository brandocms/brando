defmodule Brando.Villain.Block do
  @moduledoc """
  Use to set module as a Villain block
  """
  @callback protected_attrs() :: [atom()]
  @callback apply_ref(module(), map(), map()) :: map()

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

      # ref_src = %Ref struct, ref_target_changeset = changeset
      def apply_ref(src_type, ref_src, ref_target_changeset) do
        protected_attrs = __MODULE__.protected_attrs()

        # Get the current data from the ref changeset - it might be a struct or changeset
        current_data = get_field(ref_target_changeset, :data)

        # Ensure we have a changeset for the data
        data_changeset =
          case current_data do
            %Ecto.Changeset{} = cs -> cs
            data -> change(data)
          end

        # Extract the source attributes from ref_src.data.data (which is the block data)
        src_attrs = Map.from_struct(ref_src.data.data)
        overwritten_attrs = Map.keys(src_attrs) -- protected_attrs
        new_attrs = Map.take(src_attrs, overwritten_attrs)

        # Get the current block data and merge with new attributes
        current_block_data = get_field(data_changeset, :data)
        merged_data = Map.merge(Map.from_struct(current_block_data), new_attrs)

        # Update the data changeset
        updated_data_changeset = put_change(data_changeset, :data, merged_data)

        # Apply the data changeset to get the final block struct
        updated_block = apply_changes(updated_data_changeset)

        # Return the updated ref changeset with the applied block data
        put_change(ref_target_changeset, :data, updated_block)
      end

      defoverridable apply_ref: 3
    end
  end
end

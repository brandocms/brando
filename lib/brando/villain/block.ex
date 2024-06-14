defmodule Brando.Villain.Block do
  @moduledoc """
  Use to set module as a Villain block
  """
  @callback protected_attrs() :: [atom()]
  @callback apply_ref(module(), map(), map()) :: map()

  defmacro __using__(opts) do
    type = Keyword.fetch!(opts, :type)

    quote do
      use Ecto.Schema
      import Ecto.Changeset
      @behaviour Brando.Villain.Block
      @primary_key false

      embedded_schema do
        field :uid, :string
        field :type, :string, default: unquote(type)
        field :active, :boolean, default: true
        field :collapsed, :boolean, default: false
        field :marked_as_deleted, :boolean, default: false, virtual: true
        embeds_one :data, __MODULE__.Data, on_replace: :update
      end

      def changeset(struct, params \\ %{}) do
        struct
        |> cast(params, ~w(uid type active marked_as_deleted collapsed)a)
        |> cast_embed(:data)
        |> ensure_uid()
        |> maybe_mark_for_deletion()
      end

      defp ensure_uid(changeset) do
        case get_field(changeset, :uid) do
          nil -> put_change(changeset, :uid, Brando.Utils.generate_uid())
          uid -> changeset
        end
      end

      defp maybe_mark_for_deletion(%{changes: %{marked_as_deleted: true}} = changeset) do
        %{changeset | action: :delete}
      end

      defp maybe_mark_for_deletion(changeset), do: changeset

      def __block_type__, do: unquote(type)

      def protected_attrs, do: []
      defoverridable protected_attrs: 0

      def apply_ref(src_type, ref_src, ref_target) do
        protected_attrs = __MODULE__.protected_attrs()

        overwritten_attrs = Map.keys(ref_src.data.data) -- protected_attrs
        new_attrs = Map.take(ref_src.data.data, overwritten_attrs)
        new_data = Map.merge(ref_target.data.data, new_attrs)

        put_in(ref_target, [Access.key(:data), Access.key(:data)], new_data)
      end

      defoverridable apply_ref: 3
    end
  end
end

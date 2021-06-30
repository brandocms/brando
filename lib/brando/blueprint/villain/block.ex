defmodule Brando.Blueprint.Villain.Block do
  @moduledoc """
  Use to set module as a Villain block
  """
  defmacro __using__(opts) do
    type = Keyword.fetch!(opts, :type)

    quote do
      use Ecto.Schema
      import Ecto.Changeset

      @primary_key false

      embedded_schema do
        field :uid, :string
        field :type, :string
        field :hidden, :boolean, default: false
        field :marked_as_deleted, :boolean, default: false, virtual: true
        embeds_one :data, __MODULE__.Data
      end

      def changeset(struct, params \\ %{}) do
        struct
        |> cast(params, ~w(uid type hidden marked_as_deleted)a)
        |> cast_embed(:data)
        |> maybe_mark_for_deletion()
      end

      defp maybe_mark_for_deletion(%{changes: %{marked_as_deleted: true}} = changeset) do
        %{changeset | action: :delete}
      end

      defp maybe_mark_for_deletion(changeset), do: changeset

      def __block_type__, do: unquote(type)
    end
  end
end

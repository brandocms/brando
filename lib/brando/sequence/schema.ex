defmodule Brando.Sequence.Schema do
  @moduledoc """
  Sequencing macro for schema.

  ## Usage

      use Brando.Sequence.Schema

      schema "example" do
        sequenced()
      end

  """

  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__)

      @doc """
      Sequences ids
      """
      def sequence(ids, vals) do
        order = Enum.zip(vals, ids)
        table = __MODULE__.__schema__(:source)

        Brando.repo().transaction(fn ->
          Enum.map(order, fn {val, id} ->
            Ecto.Adapters.SQL.query(
              Brando.repo(),
              ~s(UPDATE #{table} SET "sequence" = $1 WHERE "id" = $2),
              [val, id]
            )
          end)
        end)
      end
    end
  end

  defmacro sequenced do
    quote do
      Ecto.Schema.field(:sequence, :integer, default: 0)
    end
  end
end

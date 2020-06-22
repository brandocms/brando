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
      def sequence(%{"composite_keys" => composite_keys}) do
        table = __MODULE__.__schema__(:source)

        Brando.repo().transaction(fn ->
          for {o, idx} <- Enum.with_index(composite_keys) do
            q = from t in table, update: [set: [sequence: ^idx]]

            q =
              Enum.reduce(o, q, fn {k, v}, nq ->
                from t in nq, where: field(t, ^String.to_existing_atom(k)) == ^v
              end)

            Brando.repo().update_all(q, [])
          end
        end)
      end

      def sequence(%{"ids" => ids}) do
        # standard list of ids
        vals = Range.new(0, length(ids))

        order = Enum.zip(vals, ids)
        table = __MODULE__.__schema__(:source)

        Brando.repo().transaction(fn ->
          Enum.map(order, fn {val, id} ->
            q =
              from t in table,
                where: field(t, :id) == ^id,
                update: [set: [sequence: ^val]]

            Brando.repo().update_all(q, [])
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

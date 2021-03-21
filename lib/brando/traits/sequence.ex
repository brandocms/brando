defmodule Brando.Traits.Sequence do
  @moduledoc """
  A sequenced resource
  """
  use Brando.Trait
  alias Ecto.Changeset
  import Ecto.Query

  @type changeset :: Changeset.t()

  attributes do
    attribute :sequence, :integer, default: 0
  end

  @doc """
  Sequences ids or composite keys

  With composite keys:

      sequence %{"composite_keys" => [%{"id" => 1, "additional_id" => 2}, %{...}]}

  With regular ids

      sequence %{"ids" => [3, 5, 1]}

  """
  def sequence(module, %{"composite_keys" => composite_keys}) do
    table = module.__schema__(:source)

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

    # update referenced Datasources in Villains
    Brando.Datasource.update_datasource(module)
  end

  def sequence(module, %{"ids" => keys}) do
    # standard list of ids
    vals = Range.new(0, length(keys) - 1) |> Enum.to_list()
    table = module.__schema__(:source)

    q =
      from a in table,
        join:
          numbers in fragment(
            "SELECT * FROM unnest(?, ?) AS t(key, value)",
            type(^keys, {:array, :integer}),
            type(^vals, {:array, :integer})
          ),
        on: a.id == numbers.key,
        update: [set: [sequence: numbers.value]]

    Brando.repo().update_all(q, [])

    # update referenced Datasources in Villains
    Brando.Datasource.update_datasource(module)
  end
end

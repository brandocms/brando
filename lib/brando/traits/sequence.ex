defmodule Brando.Trait.Sequenced do
  @moduledoc """
  A sequenced resource


  ## Options

      - `append: true`: Sequences the item to the last possible position.

  """
  use Brando.Trait
  alias Brando.Cache
  alias Brando.Datasource
  alias Ecto.Changeset
  import Ecto.Query

  @type changeset :: Changeset.t()

  attributes do
    attribute :sequence, :integer, default: 0
  end

  @doc """
  Sequences ids or composite keys

  With composite keys:

      sequence %{module, "composite_keys" => [%{"id" => 1, "additional_id" => 2}, %{...}]}

  With regular ids

      sequence %{module, "ids" => [3, 5, 1]}

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

    # throw out cached listings
    Cache.Query.evict_schema(module)

    # update referenced Datasources in Villains
    Datasource.update_datasource(module)
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

    # throw out cached listings
    Cache.Query.evict_schema(module)

    # update referenced Datasources in Villains
    Datasource.update_datasource(module)
  end

  def changeset_mutator(module, %{append: true}, changeset, _user, _opts) do
    Changeset.prepare_changes(changeset, fn
      %{action: :insert} = cs ->
        # set as highest sequence on insert
        seq = get_highest_sequence(module)
        Changeset.put_change(cs, :sequence, seq)

      cs ->
        cs
    end)
  end

  def changeset_mutator(_module, _config, changeset, _user, _opts) do
    changeset
  end

  def get_highest_sequence(module) do
    query =
      from t in module,
        select: t.sequence,
        order_by: [desc: t.sequence],
        limit: 1

    case Brando.repo().all(query) do
      [] -> 0
      [seq] -> seq + 1
    end
  end
end

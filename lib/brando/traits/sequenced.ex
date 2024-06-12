defmodule Brando.Trait.Sequenced do
  @moduledoc """
  A sequenced resource


  ## Options

      - `append: true`: Sequences the item to the last possible position.
      - `strict: true`: Force absolute sequential sequencing.
          The default behaviour is to set a new entry's sequence
          to 0, and order by `[asc: :sequence, desc: :inserted_at]`. This means
          we can have multiple entries with sequence 0. If you use `Query.next_entry/prev_entry`,
          this can interfere with the results. By using `strict: true`, the new entry
          will have sequence 0 and all other entries' sequences will be incremented by 1

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

  def sequence(module, %{"ids" => keys} = params) do
    offset =
      params
      |> Map.get("sortable_offset", 0)
      |> maybe_convert_to_integer()

    # standard list of ids
    vals = Range.new(0 + offset, offset + length(keys) - 1) |> Enum.to_list()
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

  def changeset_mutator(module, %{strict: true}, changeset, _user, _opts) do
    Changeset.prepare_changes(changeset, fn
      %{action: :insert} = cs ->
        language = Changeset.get_field(cs, :language)
        increase_sequence(module, language)
        Changeset.force_change(cs, :sequence, 0)

      cs ->
        cs
    end)
  end

  def changeset_mutator(module, %{append: true}, changeset, _user, _opts) do
    Changeset.prepare_changes(changeset, fn
      %{action: :insert} = cs ->
        # set as highest sequence on insert
        language = Changeset.get_field(cs, :language)
        seq = get_highest_sequence(module, language)

        Changeset.force_change(cs, :sequence, seq)
        |> dbg

      cs ->
        cs
    end)
  end

  def changeset_mutator(_module, _config, changeset, _user, _opts) do
    changeset
  end

  def increase_sequence(module, nil) do
    query = from t in module, update: [inc: [sequence: 1]]
    Brando.repo().update_all(query, [])
  end

  def increase_sequence(module, language) do
    query = from t in module, where: t.language == ^language, update: [inc: [sequence: 1]]
    Brando.repo().update_all(query, [])
  end

  def get_highest_sequence(module, language) do
    query =
      from t in module,
        select: t.sequence,
        order_by: [desc: t.sequence],
        limit: 1

    query = (language && from(t in query, where: t.language == ^language)) || query

    case Brando.repo().all(query) do
      [] -> 0
      [nil] -> 0
      [seq] -> seq + 1
    end
  end

  defp maybe_convert_to_integer(sortable_offset) when is_binary(sortable_offset) do
    {integer, _} = Integer.parse(sortable_offset)
    integer
  end

  defp maybe_convert_to_integer(sortable_offset) when is_integer(sortable_offset) do
    sortable_offset
  end
end

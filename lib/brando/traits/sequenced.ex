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
  alias Brando.Authorization.Boundary
  alias Brando.Cache
  alias Brando.Datasource
  alias Brando.Repo
  alias Brando.Trait.Sequenced.Compiler
  alias Ecto.Changeset
  import Ecto.Query

  @type changeset :: Changeset.t()

  @impl true
  def generate_code(module, config), do: Compiler.generate_code(module, config)

  @doc """
  Sequences ids or composite keys. The activity log credits `opts[:user]`,
  else `actor`, else the current authorization scope.

  With composite keys:

      sequence %{module, "composite_keys" => [%{"id" => 1, "additional_id" => 2}, %{...}]}

  With regular ids

      sequence %{module, "ids" => [3, 5, 1]}

  """
  def sequence(module, params, actor \\ nil, opts \\ []) do
    result = do_sequence(module, params, actor)
    by = Keyword.get(opts, :user) || actor || Boundary.current_scope()
    record_reorder(result, module, params, by)
    result
  end

  # One event for the whole reorder, naming the entry now first.
  defp record_reorder({:error, _}, _module, _params, _actor), do: :ok

  defp record_reorder(_result, module, params, actor) do
    keys = Map.get(params, "ids") || Enum.map(Map.get(params, "composite_keys") || [], &Map.get(&1, "id"))

    first =
      case keys do
        [first | _] -> Repo.one(from(e in module, where: e.id == ^first))
        _ -> nil
      end

    Brando.Activity.reordered(module, length(keys), first, actor)
  rescue
    _ -> :ok
  end

  defp do_sequence(module, params, actor) do
    if Brando.Authorization.enabled?() do
      actor = actor || Boundary.current_scope()

      Boundary.run(actor, :reorder, module, &authorized_sequence(module, params, &1))
    else
      legacy_sequence(module, params)
    end
  end

  defp authorized_sequence(module, params, user) do
    composites = Map.get(params, "composite_keys")
    keys = Map.get(params, "ids") || composite_ids(composites)
    if not is_list(keys) or length(keys) > 1000, do: Repo.rollback(:forbidden)
    entries = Repo.all(from(e in module, where: e.id in ^keys, lock: "FOR UPDATE"))
    if length(entries) != length(Enum.uniq(keys)), do: Repo.rollback(:forbidden)

    if composites && not Enum.all?(composites, &composite_matches?(module, entries, &1)),
      do: Repo.rollback(:forbidden)

    Enum.each(entries, &authorize_reorder!(user, &1))

    legacy_sequence(module, params)
  end

  defp composite_ids(composites) do
    if is_list(composites), do: Enum.map(composites, &Map.get(&1, "id"))
  end

  defp authorize_reorder!(user, entry) do
    changeset = Ecto.Changeset.change(entry, sequence: -1)

    unless Brando.Authorization.Engine.authorize_change(
             Boundary.actor_scope(user),
             :reorder,
             changeset
           ) == :ok,
           do: Repo.rollback(:forbidden)
  end

  # Every key of a composite must name a schema field holding that value on a
  # locked entry.
  defp composite_matches?(module, entries, keys) do
    case Enum.find(entries, &(to_string(&1.id) == to_string(keys["id"]))) do
      nil -> false
      entry -> Enum.all?(keys, &field_matches?(module, entry, &1))
    end
  end

  defp field_matches?(module, entry, {field, value}) do
    case Enum.find(module.__schema__(:fields), &(to_string(&1) == field)) do
      nil -> false
      schema_field -> to_string(Map.get(entry, schema_field)) == to_string(value)
    end
  end

  defp composite_sequence_query(table, keys, idx) do
    q = from t in table, update: [set: [sequence: ^idx]]

    Enum.reduce(keys, q, fn {k, v}, nq ->
      from t in nq, where: field(t, ^String.to_existing_atom(k)) == ^v
    end)
  end

  defp legacy_sequence(module, %{"composite_keys" => composite_keys}) do
    table = module.__schema__(:source)

    Repo.transaction(fn ->
      for {o, idx} <- Enum.with_index(composite_keys) do
        Repo.update_all(composite_sequence_query(table, o, idx), [])
      end
    end)

    # throw out cached listings
    Cache.Query.evict_schema(module)

    # update referenced Datasources in Villains
    Datasource.update_datasource(module)
  end

  defp legacy_sequence(module, %{"ids" => keys} = params) do
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

    Repo.update_all(q, [])

    # throw out cached listings
    Cache.Query.evict_schema(module)

    # update referenced Datasources in Villains
    Datasource.update_datasource(module)
  end

  @impl true
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

      cs ->
        cs
    end)
  end

  def changeset_mutator(_module, _config, changeset, _user, _opts) do
    changeset
  end

  def increase_sequence(module, nil) do
    query = from t in module, update: [inc: [sequence: 1]]
    Repo.update_all(query, [])
  end

  def increase_sequence(module, language) do
    query = from t in module, where: t.language == ^language, update: [inc: [sequence: 1]]
    Repo.update_all(query, [])
  end

  def get_highest_sequence(module, language) do
    query =
      from t in module,
        select: t.sequence,
        order_by: [desc: t.sequence],
        limit: 1

    query = (language && from(t in query, where: t.language == ^language)) || query

    case Repo.all(query) do
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

defmodule Brando.Translations.Pairing do
  @moduledoc """
  Links the language versions of entries matched by their values, for a
  schema declared with `trait :translatable, matched_by: [...]`, such as
  fragments by their parent key and key: `mix brando.fragments.pair`.

  `plan/1` changes nothing. It sorts the entries not in the trash into
  groups of the same values, and says of each group what linking it takes:

    * `:link`: the links the group lacks, both directions of every pair of
      its entries; a link left one way only is completed;
    * `:linked`: nothing, every entry is linked to every other already;
    * `:same_language`: refused, two entries of the group share a language;
    * `:one_language`: nothing to link, the values exist in one language;
    * `:linked_elsewhere`: refused, an entry of the group is linked to an
      entry outside it (with other values, or in the trash). Such a link is
      an editor's decision, and is never extended.

  `apply/2` writes the links of each `:link` group in a transaction of its
  own, after checking that the group is as the plan saw it: an entry
  renamed, moved to another language, trashed or deleted, or linked by an
  editor since, leaves the group as it is, reported as `:changed`. Linking
  copies no content and joins no synchronized group. What follows a link
  (`Brando.Translations.alternate_added/3`) is re-synchronized for every
  linked group, those linked already included, so a run that stopped before
  that is repaired by the next.
  """

  import Ecto.Query

  alias Brando.Cache.Query, as: CacheQuery
  alias Brando.Repo
  alias Brando.Translations

  @type group :: %{
          values: [term()],
          status: :link | :linked | :same_language | :one_language | :linked_elsewhere,
          entries: [%{id: integer(), language: String.t()}],
          links: [{integer(), integer()}],
          missing: [{integer(), integer()}]
        }

  @doc "The groups of `schema`'s entries by their `matched_by` values, and what linking each takes."
  @spec plan(module()) :: [group()]
  def plan(schema) do
    fields = fields!(schema)
    entries = candidates(schema, fields)
    values_by_id = Map.new(entries, &{&1.id, &1.values})

    links_by_values =
      schema
      |> links(Map.keys(values_by_id))
      |> Enum.flat_map(fn {a, b} = link ->
        # A link across groups belongs to both. A trashed endpoint has no group.
        for values <- Enum.uniq([values_by_id[a], values_by_id[b]]), values != nil, do: {values, link}
      end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    entries
    |> Enum.group_by(& &1.values)
    |> Enum.sort_by(fn {values, _} -> Enum.map(values, &to_string/1) end)
    |> Enum.map(fn {values, group} ->
      group(values, Enum.sort_by(group, &{&1.language, &1.id}), Map.get(links_by_values, values, []))
    end)
  end

  @doc """
  Writes the links of the plan's `:link` groups. Returns each of those groups
  with `status` set to `:linked` once written, or `:changed` when it no longer
  is as the plan saw it.
  """
  @spec apply(module(), [group()]) :: [group()]
  def apply(schema, plan) do
    fields = fields!(schema)

    # Again for a group linked already: a run that stopped after writing its
    # links may not have re-synchronized what follows them
    for %{status: :linked, links: links} <- plan, do: linked(schema, Enum.uniq_by(links, &Enum.sort(Tuple.to_list(&1))))

    for %{status: :link} = group <- plan, do: apply_group(schema, fields, group)
  end

  defp apply_group(schema, fields, group) do
    case Repo.transaction(fn -> link_group(schema, fields, group) end) do
      {:ok, pairs} ->
        linked(schema, pairs)
        %{group | status: :linked}

      {:error, :changed} ->
        %{group | status: :changed}
    end
  end

  defp fields!(schema) do
    case Translations.matched_by(schema) do
      [] ->
        raise ArgumentError, "#{inspect(schema)} declares no trait :translatable, matched_by: [...]"

      fields ->
        if schema.has_alternates?(), do: fields, else: raise(ArgumentError, "#{inspect(schema)} has no alternates")
    end
  end

  defp candidates(schema, fields, ids \\ nil, lock? \\ false) do
    # The language as stored: one the site no longer lists still counts
    query = from(e in schema, select: map(e, ^[:id | fields]), select_merge: %{language: type(e.language, :string)})
    query = if :deleted_at in schema.__schema__(:fields), do: where(query, [e], is_nil(e.deleted_at)), else: query
    query = if ids, do: where(query, [e], e.id in ^ids), else: query
    query = if lock?, do: lock(query, "FOR UPDATE"), else: query

    query
    |> Repo.all()
    |> Enum.map(&%{id: &1.id, language: &1.language, values: Enum.map(fields, fn f -> Map.get(&1, f) end)})
  end

  # Every link that touches one of `ids`, either way, as `{entry_id, linked_entry_id}`
  defp links(schema, ids) do
    Repo.all(
      from a in Module.concat(schema, Alternate),
        where: a.entry_id in ^ids or a.linked_entry_id in ^ids,
        select: {a.entry_id, a.linked_entry_id},
        order_by: [asc: a.entry_id, asc: a.linked_entry_id]
    )
  end

  defp group(values, entries, touching) do
    ids = MapSet.new(entries, & &1.id)
    pairs = for %{id: a} <- entries, %{id: b} <- entries, a != b, do: {a, b}
    missing = pairs -- touching

    status =
      cond do
        length(Enum.uniq_by(entries, & &1.language)) < length(entries) -> :same_language
        length(entries) == 1 -> :one_language
        Enum.any?(touching, fn {a, b} -> a not in ids or b not in ids end) -> :linked_elsewhere
        missing == [] -> :linked
        true -> :link
      end

    %{values: values, status: status, entries: entries, links: touching, missing: missing}
  end

  # The group as it is now: its entries, locked, with their values and
  # languages, no other entry with its values, and the links the plan saw
  defp link_group(schema, fields, %{values: values, entries: entries, links: links, missing: missing}) do
    ids = Enum.map(entries, & &1.id)
    current = schema |> candidates(fields, ids, true) |> Enum.sort_by(&{&1.language, &1.id})

    if current == entries and same_values_ids(schema, fields, values) == Enum.sort(ids) and links(schema, ids) == links do
      now = NaiveDateTime.utc_now(:second)
      rows = for {a, b} <- missing, do: %{entry_id: a, linked_entry_id: b, inserted_at: now, updated_at: now}
      Repo.insert_all(Module.concat(schema, Alternate), rows)
      Enum.uniq_by(missing, fn {a, b} -> Enum.sort([a, b]) end)
    else
      Repo.rollback(:changed)
    end
  end

  defp same_values_ids(schema, fields, values) do
    fields
    |> Enum.zip(values)
    |> Enum.reduce(from(e in schema, select: e.id, order_by: e.id), fn
      {field, nil}, query -> where(query, [e], is_nil(field(e, ^field)))
      {field, value}, query -> where(query, [e], field(e, ^field) == ^value)
    end)
    |> then(&if(:deleted_at in schema.__schema__(:fields), do: where(&1, [e], is_nil(e.deleted_at)), else: &1))
    |> Repo.all()
  end

  # As `Alternate.add/3` does once its rows are in
  defp linked(schema, pairs) do
    for {a, b} <- pairs do
      CacheQuery.evict_entry(schema, a)
      CacheQuery.evict_entry(schema, b)
      Translations.alternate_added(schema, a, b)
    end
  end
end

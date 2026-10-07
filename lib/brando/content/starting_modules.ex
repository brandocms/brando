defmodule Brando.Content.StartingModules do
  @moduledoc """
  The modules an empty block field offers to start with: what entries of the
  same kind usually begin with.

  The ranking answers "what does this field usually start with?", not "what
  is used most?". Text and image modules are the most used almost everywhere
  but rarely come first, so ranking by overall use would put them first on
  every field. For a block field, across the entries in one language (soft
  deleted entries left out):

    1. modules pinned with the field's `starts_with:` option, in that order
       (see `blocks` in `Brando.Blueprint.Forms`);
    2. the modules that came first, most often first, each with its count
       ("first in 34 of 41"). When the first root block is a container, the
       container is counted together with its first module;
    3. if that leaves free slots, the field's most used modules, without a
       count — useful as a second block, never ahead of a first-position one;
    4. then the offered modules in their own order.

  With fewer than five entries that have blocks in the field, there is too
  little to go on: the offered modules are shown in their own order, without
  counts.

  Only the modules passed in are offered: the ones the site has enabled and
  the field's module set allows, in the order the module picker lists them.

  Counts are read with two grouped queries and cached per site, field and
  language for a few minutes (`counts/2`). Nothing is read for a field that
  already has blocks; the block editor only asks while the field is empty.
  """

  import Ecto.Query

  alias Brando.Content.Block
  alias Brando.Content.SharedLibrary
  alias Brando.Repo

  @limit 4
  @min_entries 5
  @ttl :timer.minutes(5)

  @typedoc "A module or container, as `{origin, id}`."
  @type ref :: {:local | :shared, integer()}

  @type counts :: %{
          entries: non_neg_integer(),
          first: [{{ref(), ref() | nil}, pos_integer()}],
          used: [{ref(), pos_integer()}]
        }

  @type tile :: %{
          module: map(),
          module_ref: String.t(),
          container: map() | nil,
          container_ref: String.t() | nil,
          count: pos_integer() | nil,
          of: pos_integer() | nil
        }

  @doc """
  The tiles for an empty block field: up to four modules from `modules`
  (the modules offered at the field's root, in their order).

  `block_module` is the field's join schema (`MyApp.Cases.Case.Blocks`).

  Options:

    * `:language` — the entry's language; entries in other languages are not
      counted. Ignored for schemas without a language.
    * `:starts_with` — module classes to pin to the front, in order.
    * `:limit` — how many tiles, four by default.
  """
  @spec list(module(), [map()], keyword()) :: [tile()]
  def list(block_module, modules, opts \\ []) do
    counts = counts(block_module, opts[:language])
    rank(counts, modules, Keyword.put(opts, :containers, containers(counts)))
  end

  @doc """
  The first-position and overall-use counts for a field, cached for a few
  minutes under `cache_key/2` (per site through `Brando.Cache`).
  """
  @spec counts(module(), atom() | String.t() | nil) :: counts()
  def counts(block_module, language) do
    key = cache_key(block_module, language)

    case Brando.Cache.get(key) do
      %{entries: _} = counts ->
        counts

      _ ->
        counts = count(block_module, language)
        Brando.Cache.put(key, counts, @ttl)
        counts
    end
  end

  @doc """
  The cache key for a field's counts in a language. `Brando.Cache` adds the
  site (tenant) around it.
  """
  @spec cache_key(module(), atom() | String.t() | nil) :: term()
  def cache_key(block_module, language), do: {:starting_modules, block_module, language && to_string(language)}

  @doc "Reads the counts from the database, uncached. See `counts/2`."
  @spec count(module(), atom() | String.t() | nil) :: counts()
  def count(block_module, language) do
    first = count_first(block_module, language)
    entries = Enum.reduce(first, 0, fn {_key, count}, acc -> acc + count end)

    %{
      entries: entries,
      first:
        for(
          {{module_ref, container_ref}, count} <- first,
          module_ref != nil,
          do: {{module_ref, container_ref}, count}
        ),
      used: if(entries >= @min_entries, do: count_used(block_module, language), else: [])
    }
  end

  @doc """
  Ranks `modules` by `counts`. Pure: `list/3` reads the counts and the
  containers they name and calls this.

  Takes the same options as `list/3`, and `:containers`, a map of container
  `ref` to container, for the containers that come first.
  """
  @spec rank(counts(), [map()], keyword()) :: [tile()]
  def rank(counts, modules, opts \\ []) do
    containers = Keyword.get(opts, :containers, %{})
    by_ref = Map.new(modules, &{module_ref(&1), &1})
    # Too little content to go on: nothing is counted.
    counts = if counts.entries >= @min_entries, do: counts, else: %{counts | first: [], used: []}

    pinned =
      for class <- List.wrap(opts[:starts_with]),
          module <- modules,
          module.class == to_string(class),
          do: {module_ref(module), nil}

    first =
      counts.first
      |> Enum.filter(fn {{module_ref, container_ref}, _count} ->
        Map.has_key?(by_ref, module_ref) and (is_nil(container_ref) or Map.has_key?(containers, container_ref))
      end)
      |> by_count(modules, fn {{module_ref, _}, _} -> module_ref end)
      |> Enum.map(&elem(&1, 0))

    used =
      counts.used
      |> Enum.filter(fn {module_ref, _count} -> Map.has_key?(by_ref, module_ref) end)
      |> by_count(modules, &elem(&1, 0))
      |> Enum.map(&{elem(&1, 0), nil})

    first_counts = Map.new(counts.first)

    (pinned ++ first)
    |> Enum.uniq()
    |> fill(used ++ Enum.map(modules, &{module_ref(&1), nil}))
    |> Enum.take(Keyword.get(opts, :limit, @limit))
    |> Enum.map(&tile(&1, Map.get(first_counts, &1), counts.entries, by_ref, containers))
  end

  # Most counted first; ties in the modules' own order.
  defp by_count(counted, modules, module_ref) do
    Enum.sort_by(counted, fn {_key, count} = item -> {-count, position(modules, module_ref.(item))} end)
  end

  defp tile({module_ref, container_ref}, count, entries, by_ref, containers) do
    %{
      module: Map.fetch!(by_ref, module_ref),
      module_ref: encode(module_ref),
      container: container_ref && Map.fetch!(containers, container_ref),
      container_ref: container_ref && encode(container_ref),
      count: count,
      of: count && entries
    }
  end

  # Fillers only add modules not already offered, with or without a container.
  defp fill(tiles, fillers) do
    Enum.reduce(fillers, tiles, fn {module_ref, nil} = filler, acc ->
      if Enum.any?(acc, &(elem(&1, 0) == module_ref)), do: acc, else: acc ++ [filler]
    end)
  end

  defp position(modules, module_ref), do: Enum.find_index(modules, &(module_ref(&1) == module_ref)) || length(modules)

  defp module_ref(module), do: {Map.get(module, :library_origin) || :local, module.id}

  defp encode({origin, id}), do: SharedLibrary.encode_reference(origin, id)

  defp containers(%{entries: entries, first: first}) when entries >= @min_entries do
    for {{_module_ref, {origin, id} = container_ref}, _count} <- first,
        container = Brando.Content.fetch_container(id, origin),
        into: %{},
        do: {container_ref, container}
  end

  defp containers(_counts), do: %{}

  # One row per (first block, first module inside it), counted. Each entry
  # with blocks in the field has exactly one first root block, so the counts
  # add up to the number of entries.
  defp count_first(block_module, language) do
    first_roots =
      block_module
      |> entries(language)
      |> distinct([j], j.entry_id)
      |> order_by([j], asc: j.entry_id, asc: j.sequence, asc: j.id)
      |> select([j], %{block_id: j.block_id})

    first_child =
      from c in Block,
        where: c.parent_id == parent_as(:root).id and c.type == :module,
        order_by: [asc: c.sequence, asc: c.id],
        limit: 1,
        select: %{module_id: c.module_id, module_origin: c.module_origin}

    from(f in subquery(first_roots),
      join: b in Block,
      as: :root,
      on: b.id == f.block_id,
      left_lateral_join: c in subquery(first_child),
      on: true,
      group_by: [b.type, b.module_id, b.module_origin, b.container_id, b.container_origin, c.module_id, c.module_origin],
      select:
        {b.type, b.module_id, b.module_origin, b.container_id, b.container_origin, c.module_id, c.module_origin, count()}
    )
    |> Repo.all()
    |> Enum.map(&first_key/1)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {key, counts} -> {key, Enum.sum(counts)} end)
  end

  defp first_key({:module, module_id, module_origin, _, _, _, _, count}) when not is_nil(module_id),
    do: {{{module_origin || :local, module_id}, nil}, count}

  defp first_key({:container, _, _, container_id, container_origin, module_id, module_origin, count})
       when not is_nil(container_id) and not is_nil(module_id),
       do: {{{module_origin || :local, module_id}, {container_origin || :local, container_id}}, count}

  # A fragment, an empty container, a slot: the entry has blocks, but nothing
  # a tile could offer comes first.
  defp first_key({_type, _, _, _, _, _, _, count}), do: {{nil, nil}, count}

  # Root modules, and modules directly inside root containers.
  defp count_used(block_module, language) do
    block_module
    |> entries(language)
    |> join(:inner, [j], b in Block, on: b.id == j.block_id)
    |> join(:left, [_j, _e, b], c in Block, on: c.parent_id == b.id and b.type == :container and c.type == :module)
    |> where([_j, _e, b, c], b.type == :module or not is_nil(c.id))
    |> group_by([_j, _e, b, c], [coalesce(c.module_id, b.module_id), coalesce(c.module_origin, b.module_origin)])
    |> select([_j, _e, b, c], {coalesce(c.module_origin, b.module_origin), coalesce(c.module_id, b.module_id), count()})
    |> Repo.all()
    |> Enum.map(fn {origin, id, count} -> {{origin || :local, id}, count} end)
  end

  # The field's join rows, for live entries in the language.
  defp entries(block_module, language) do
    schema = block_module.__schema__(:association, :entry).related
    fields = schema.__schema__(:fields)

    block_module
    |> join(:inner, [j], e in ^schema, on: e.id == j.entry_id)
    |> then(fn query ->
      if :deleted_at in fields, do: where(query, [_j, e], is_nil(e.deleted_at)), else: query
    end)
    |> then(fn query ->
      if :language in fields and not is_nil(language),
        do: where(query, [_j, e], field(e, :language) == ^language),
        else: query
    end)
  end
end

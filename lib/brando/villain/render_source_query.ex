defmodule Brando.Villain.RenderSourceQuery do
  @moduledoc """
  Read-only content queries used by the Villain rendering pipeline.

  Rendering only needs modules, containers, and palettes. Keeping those reads
  separate from `Brando.Content` prevents rendering from depending on the full
  content mutation and block-orchestration context.
  """

  import Ecto.Query, only: [from: 2, preload: 2]

  alias Brando.Cache.Query, as: QueryCache
  alias Brando.Repo

  @module_schema Module.concat(["Brando", "Content", "Module"])
  @container_schema Module.concat(["Brando", "Content", "Container"])
  @palette_schema Module.concat(["Brando", "Content", "Palette"])

  @doc """
  Lists non-deleted content modules for rendering.

  Accepts the rendering pipeline's `:preload` and `:cache` options. Cache keys
  match `Brando.Content.list_modules/1`, so existing mutation-driven eviction
  remains effective.
  """
  @spec list_modules(map()) :: {:ok, [struct()]}
  def list_modules(opts \\ %{}), do: list(@module_schema, opts)

  @doc """
  Lists non-deleted content containers for rendering.

  Cache keys remain compatible with `Brando.Content.list_containers/1`.
  """
  @spec list_containers(map()) :: {:ok, [struct()]}
  def list_containers(opts \\ %{}), do: list(@container_schema, opts)

  @doc """
  Lists non-deleted content palettes for rendering.

  Cache keys remain compatible with `Brando.Content.list_palettes/1`.
  """
  @spec list_palettes(map()) :: {:ok, [struct()]}
  def list_palettes(opts \\ %{}), do: list(@palette_schema, opts)

  defp list(schema, opts) when is_map(opts) do
    query =
      from entry in schema,
        where: is_nil(entry.deleted_at)

    query = maybe_preload(query, Map.get(opts, :preload))
    query_key = {:list, schema.__schema__(:source), opts}

    case QueryCache.try_cache(query_key, Map.get(opts, :cache)) do
      {:miss, cache_key, ttl} ->
        entries = Repo.all(query)
        QueryCache.put(cache_key, entries, ttl)
        {:ok, entries}

      {:hit, entries} ->
        {:ok, entries}

      :no_cache ->
        {:ok, Repo.all(query)}
    end
  end

  defp maybe_preload(query, nil), do: query
  defp maybe_preload(query, preloads), do: preload(query, ^preloads)
end

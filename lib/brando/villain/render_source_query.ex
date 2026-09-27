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
  alias Brando.Villain.RenderScope

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
  Fetches one local module without copying the module library on cache hits.

  The key shares the list eviction namespace, so module changes and schema
  eviction invalidate these projections alongside the existing list cache.
  Cold projections reuse the library cache to avoid one preload query batch
  per distinct module. Tenant shared/local resolution remains owned by
  SharedLibrary.
  """
  def get_module(nil, _opts), do: nil

  def get_module(id, opts) do
    RenderScope.fetch({__MODULE__, :module, id, opts}, fn ->
      query_key = {:list, @module_schema.__schema__(:source), Map.put(opts, :render_module_id, id)}

      case QueryCache.try_cache(query_key, Map.get(opts, :cache)) do
        {:miss, cache_key, ttl} ->
          {:ok, modules} = list_modules(opts)
          entry = Enum.find(modules, &(&1.id == id))
          QueryCache.put(cache_key, entry, ttl)
          entry

        {:hit, entry} ->
          entry

        :no_cache ->
          load_module(id, opts)
      end
    end)
  end

  defp load_module(id, opts) do
    query = from entry in @module_schema, where: entry.id == ^id and is_nil(entry.deleted_at)
    query |> maybe_preload(Map.get(opts, :preload)) |> Repo.one()
  end

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
    RenderScope.fetch({__MODULE__, schema, opts}, fn -> do_list(schema, opts) end)
  end

  defp do_list(schema, opts) do
    kind = tenant_library_kind(schema)

    if kind && Brando.Tenant.enabled?() do
      {:ok, Brando.Content.SharedLibrary.list_for_current_tenant(kind)}
    else
      list_from_current_prefix(schema, opts)
    end
  end

  defp list_from_current_prefix(schema, opts) do
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

  defp tenant_library_kind(@module_schema), do: :module
  defp tenant_library_kind(@container_schema), do: :container
  defp tenant_library_kind(@palette_schema), do: :palette
  defp tenant_library_kind(_schema), do: nil

  defp maybe_preload(query, nil), do: query

  defp maybe_preload(query, preloads) do
    preloads =
      Enum.map(List.wrap(preloads), fn
        {assoc, {schema, order}} when is_atom(schema) and is_list(order) ->
          {assoc, from(entry in schema, order_by: ^order)}

        preload ->
          preload
      end)

    preload(query, ^preloads)
  end
end

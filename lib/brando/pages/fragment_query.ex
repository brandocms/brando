defmodule Brando.Pages.FragmentQuery do
  @moduledoc """
  Read-only fragment queries used by the rendering pipeline.

  Keeping this path separate from `Brando.Pages` prevents Villain rendering
  from depending on the full page and fragment mutation context, including
  its admin and content-rendering callbacks.
  """

  import Ecto.Query, only: [from: 2]

  alias Brando.Cache.Query, as: QueryCache
  alias Brando.Repo

  @fragment_schema Module.concat(["Brando", "Pages", "Fragment"])

  @doc """
  Lists renderable fragments in their canonical rendering order.

  Accepts the same cache option used by `Brando.Pages.list_fragments/1`, so
  query-cache entries and mutation-driven invalidation remain compatible.
  """
  @spec list_for_rendering(map()) :: {:ok, [struct()]}
  def list_for_rendering(opts \\ %{}) when is_map(opts) do
    fragment_schema = @fragment_schema

    query =
      from fragment in fragment_schema,
        where: is_nil(fragment.deleted_at),
        order_by: [asc: fragment.parent_key, asc: fragment.sequence, asc: fragment.language]

    query_key = {:list, fragment_schema.__schema__(:source), opts}

    case QueryCache.try_cache(query_key, Map.get(opts, :cache)) do
      {:miss, cache_key, ttl} ->
        fragments = Repo.all(query)
        QueryCache.put(cache_key, fragments, ttl)
        {:ok, fragments}

      {:hit, fragments} ->
        {:ok, fragments}

      :no_cache ->
        {:ok, Repo.all(query)}
    end
  end
end

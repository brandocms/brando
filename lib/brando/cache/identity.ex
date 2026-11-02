defmodule Brando.Cache.Identity do
  @moduledoc """
  Interaction with identity cache
  """
  use Brando.Tracing.Decorator

  alias Brando.Cache
  alias Brando.Sites

  # Services are resolved against their linked entries here, once, so page
  # renders and the JSON-LD graph read them without a query.
  @preloads [:logo, services: :identifier]

  @type identity :: Brando.Sites.Identity.t()
  @type changeset :: Ecto.Changeset.t()

  @doc """
  Get Identity from cache
  """
  @spec get(binary()) :: map()
  def get(language) do
    identity_map =
      case Cache.get_site(:identity) do
        nil -> set()
        cache -> cache
      end

    Map.get(identity_map, language, %{})
  end

  @doc """
  Set initial identity cache. Called on startup
  """
  @spec set :: map()
  @decorate span("brando.cache.set_identity")
  def set do
    if Brando.Tenant.outside_site?(), do: %{}, else: Cache.serialize(:identity, &do_set/0)
  end

  defp do_set do
    {:ok, identities} = Sites.list_identities(%{preload: @preloads})
    identity_map = process_identities(identities)
    Cache.put(:identity, identity_map, :infinite)
    identity_map
  end

  @doc """
  Update identitys cache, once the transaction around the caller has
  committed (`Brando.Cache.rebuild_after_commit/1`)
  """
  @spec update({:ok, any()} | {:error, changeset}) ::
          {:ok, map()} | {:error, changeset}
  def update({:ok, identity}) do
    Cache.rebuild_after_commit(:identity)
    {:ok, identity}
  end

  def update({:error, changeset}), do: {:error, changeset}

  @doc false
  # Under `Brando.Cache`'s lock for the cache
  def rebuild do
    {:ok, identities} = Sites.list_identities(%{preload: @preloads})
    Cache.update(:identity, process_identities(identities))
  end

  defp process_identities(identities) do
    Enum.reduce(identities, %{}, fn
      %{language: language} = identity, acc ->
        put_in(acc, [Brando.Utils.access_map(to_string(language))], Brando.Sites.Services.resolve_all(identity))
    end)
  end
end

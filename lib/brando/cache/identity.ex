defmodule Brando.Cache.Identity do
  @moduledoc """
  Interaction with identity cache
  """
  alias Brando.Cache
  alias Brando.Sites

  @type identity :: Brando.Sites.Identity.t()
  @type changeset :: Ecto.Changeset.t()

  @doc """
  Get Identity from cache
  """
  @spec get(binary()) :: map()
  def get(language), do: Map.get(Cache.get(:identity), language, %{})

  @doc """
  Set initial identity cache. Called on startup
  """
  @spec set :: {:error, boolean} | {:ok, boolean}
  def set do
    {:ok, identities} = Sites.list_identities(%{preload: [:logo]})
    identity_map = process_identities(identities)
    Cachex.put(:cache, :identity, identity_map)
  end

  @doc """
  Update identitys cache
  """
  @spec update({:ok, any()} | {:error, changeset}) ::
          {:ok, map()} | {:error, changeset}
  def update({:ok, identity}) do
    {:ok, identities} = Sites.list_identities(%{preload: [:logo]})
    identity_map = process_identities(identities)
    Cachex.update(:cache, :identity, identity_map)
    {:ok, identity}
  end

  def update({:error, changeset}), do: {:error, changeset}

  defp process_identities(identities) do
    Enum.reduce(identities, %{}, fn
      %{language: language} = identity, acc ->
        put_in(
          acc,
          [
            Brando.Utils.access_map(to_string(language))
          ],
          identity
        )
    end)
  end
end

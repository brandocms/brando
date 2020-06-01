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
  @spec get :: {:ok, identity}
  def get, do: Cache.get(:identity)

  @doc """
  Set initial identity cache. Called on startup
  """
  @spec set :: {:error, boolean} | {:ok, boolean}
  def set do
    {:ok, identity} = Sites.get_identity()
    Cachex.put(:cache, :identity, identity)
  end

  @doc """
  Update identity cache
  """
  @spec update({:ok, identity} | {:error, changeset}) ::
          {:ok, identity} | {:error, changeset}
  def update({:ok, updated_identity}) do
    Cachex.update(:cache, :identity, updated_identity)
    {:ok, updated_identity}
  end

  def update({:error, changeset}), do: {:error, changeset}
end

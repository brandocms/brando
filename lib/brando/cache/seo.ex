defmodule Brando.Cache.SEO do
  @moduledoc """
  Interaction with SEO cache
  """
  alias Brando.Cache
  alias Brando.Sites

  @type seo :: Brando.Sites.SEO.t()
  @type changeset :: Ecto.Changeset.t()

  @doc """
  Get Identity from cache
  """
  @spec get :: seo
  def get, do: Cache.get(:seo)

  @doc """
  Set initial seo cache. Called on startup
  """
  @spec set :: {:error, boolean} | {:ok, boolean}
  def set do
    {:ok, seo} = Sites.get_seo()
    Cachex.put(:cache, :seo, seo)
  end

  @doc """
  Update seo cache
  """
  @spec update({:ok, seo} | {:error, changeset}) ::
          {:ok, seo} | {:error, changeset}
  def update({:ok, updated_seo}) do
    Cachex.update(:cache, :seo, updated_seo)
    {:ok, updated_seo}
  end

  def update({:error, changeset}), do: {:error, changeset}
end

defmodule Brando.Cache.SEO do
  @moduledoc """
  Interaction with SEO cache
  """
  alias Brando.Cache
  alias Brando.Sites

  @type seo :: Brando.Sites.SEO.t()
  @type changeset :: Ecto.Changeset.t()

  @doc """
  Get SEO from cache
  """
  @spec get(binary()) :: map()
  def get(language), do: Map.get(Cache.get(:seo), language, %{})

  @doc """
  Set initial SEO cache. Called on startup
  """
  @spec set :: {:error, boolean} | {:ok, boolean}
  def set do
    {:ok, seos} = Sites.list_seos()
    seo_map = process_seos(seos)
    Cachex.put(:cache, :seo, seo_map)
  end

  @doc """
  Update seos cache
  """
  @spec update({:ok, any()} | {:error, changeset}) ::
          {:ok, map()} | {:error, changeset}
  def update({:ok, seo}) do
    {:ok, seos} = Sites.list_seos()
    seo_map = process_seos(seos)
    Cachex.update(:cache, :seo, seo_map)
    {:ok, seo}
  end

  def update({:error, changeset}), do: {:error, changeset}

  defp process_seos(seos) do
    Enum.reduce(seos, %{}, fn
      %{language: language} = seo, acc ->
        put_in(
          acc,
          [
            Brando.Utils.access_map(to_string(language))
          ],
          seo
        )
    end)
  end
end

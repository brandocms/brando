defmodule Brando.Cache.SEO do
  @moduledoc """
  Interaction with SEO cache
  """
  use Brando.Tracing.Decorator

  alias Brando.Cache
  alias Brando.Sites

  @type seo :: Brando.Sites.SEO.t()
  @type changeset :: Ecto.Changeset.t()

  @empty_seo %Sites.SEO{
    fallback_meta_image: nil
  }

  @doc """
  Get SEO from cache
  """

  @spec get(binary()) :: map()
  def get(language) do
    seo_map =
      case Cache.get_site(:seo) do
        nil -> set()
        cache -> cache
      end

    Map.get(seo_map || %{}, language, @empty_seo)
  end

  @doc """
  Set initial SEO cache. Called on startup
  """
  @spec set :: map()
  @decorate span("brando.cache.set_seo")
  def set do
    if Brando.Tenant.outside_site?(), do: %{}, else: Cache.fill(:seo)[:seo]
  end

  @doc """
  Update seos cache, once the transaction around the caller has committed
  (`Brando.Cache.rebuild_after_commit/1`)
  """
  @spec update({:ok, any()} | {:error, changeset}) ::
          {:ok, map()} | {:error, changeset}
  def update({:ok, seo}) do
    Cache.rebuild_after_commit(:seo)
    {:ok, seo}
  end

  def update({:error, changeset}), do: {:error, changeset}

  @doc false
  # What `Brando.Cache` stores for the cache
  def load do
    {:ok, seos} = Sites.list_seos(%{preload: [:fallback_meta_image]})
    [seo: process_seos(seos)]
  end

  defp process_seos(seos) do
    Enum.reduce(seos, %{}, fn
      %{language: language} = seo, acc ->
        put_in(acc, [Brando.Utils.access_map(to_string(language))], seo)
    end)
  end
end

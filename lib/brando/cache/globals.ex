defmodule Brando.Cache.Globals do
  @moduledoc """
  Interaction with globals cache

  Globals get stored as a map with a key path
  """
  alias Brando.Cache
  alias Brando.Sites

  @type changeset :: Ecto.Changeset.t()

  @doc """
  Get globals from cache
  """
  @spec get(binary()) :: map()
  def get(language) do
    globals_map =
      case Cache.get(:globals) do
        nil -> set()
        cache -> cache
      end

    Map.get(globals_map || %{}, language, %{})
  end

  @doc """
  Set initial globals cache. Called on startup
  """
  @spec set :: map()
  def set do
    {:ok, global_sets} = Sites.list_global_sets()
    global_map = process_globals(global_sets)
    Cachex.put(:cache, :globals, global_map)
    global_map
  end

  @doc """
  Update globals cache
  """
  @spec update({:ok, any()} | {:error, changeset}) ::
          {:ok, map()} | {:error, changeset}
  def update({:ok, global_set}) do
    {:ok, global_sets} = Sites.list_global_sets()
    global_map = process_globals(global_sets)
    Cachex.update(:cache, :globals, global_map)

    {:ok, global_set}
  end

  def update({:error, changeset}), do: {:error, changeset}

  defp process_globals(global_sets) do
    Enum.reduce(global_sets, %{}, fn
      %{language: language, vars: vars} = set, acc when vars in [nil, []] ->
        put_in(
          acc,
          [
            Brando.Utils.access_map(to_string(language)),
            Brando.Utils.access_map(set.key)
          ],
          []
        )

      %{language: language, vars: vars} = set, acc ->
        set_globals =
          vars
          |> Enum.map(&preload_images/1)
          |> Enum.map(&{&1.key, &1})
          |> Enum.into(%{})

        put_in(
          acc,
          [
            Brando.Utils.access_map(to_string(language)),
            Brando.Utils.access_map(set.key)
          ],
          set_globals
        )
    end)
  end

  defp preload_images(%Brando.Content.Var{type: :image} = image_var),
    do: Brando.repo().preload(image_var, :image)

  defp preload_images(var), do: var
end

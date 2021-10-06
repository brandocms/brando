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
  @spec get :: map()
  def get, do: Cache.get(:globals)

  @doc """
  Set initial globals cache. Called on startup
  """
  @spec set :: {:error, boolean} | {:ok, boolean}
  def set do
    {:ok, global_sets} = Sites.list_global_sets()
    global_map = process_globals(global_sets)
    Cachex.put(:cache, :globals, global_map)
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
    Enum.map(global_sets, fn
      %{globals: nil} = cat ->
        {cat.key, []}

      cat ->
        globals_for_cat =
          cat.globals
          |> Enum.map(&{&1.key, &1})
          |> Enum.into(%{})

        {cat.key, globals_for_cat}
    end)
    |> Enum.into(%{})
  end
end

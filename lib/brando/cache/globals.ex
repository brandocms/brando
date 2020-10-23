defmodule Brando.Cache.Globals do
  @moduledoc """
  Interaction with globals cache

  Globals get stored as a map with a key path
  """
  alias Brando.Cache
  alias Brando.Globals

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
    {:ok, global_categories} = Globals.get_global_categories()
    global_map = process_globals(global_categories)
    Cachex.put(:cache, :globals, global_map)
  end

  @doc """
  Update globals cache
  """
  @spec update({:ok, any()} | {:error, changeset}) ::
          {:ok, map()} | {:error, changeset}
  def update({:ok, global_category}) do
    {:ok, global_categories} = Globals.get_global_categories()
    global_map = process_globals(global_categories)
    Cachex.update(:cache, :globals, global_map)
    {:ok, global_category}
  end

  def update({:error, changeset}), do: {:error, changeset}

  defp process_globals(global_categories) do
    Enum.map(global_categories, fn cat ->
      globals_for_cat =
        cat.globals
        |> Enum.map(&{&1.key, &1})
        |> Enum.into(%{})

      {cat.key, globals_for_cat}
    end)
    |> Enum.into(%{})
  end
end

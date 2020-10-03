defmodule Brando.Cache.Navigation do
  @moduledoc """
  Interaction with navigation cache
  """
  alias Brando.Cache
  alias Brando.Navigation

  @type changeset :: Ecto.Changeset.t()

  @doc """
  Get all menus from cache
  """
  @spec get :: map()
  def get, do: Cache.get(:navigation)

  @doc """
  Get menu from cache by path
  Menu path is the key of the menu plus language seperated by a dot i.e:

      get("main.en")
  """
  @spec get(binary) :: map()
  def get(menu_path), do: Map.get(get(), menu_path)

  @doc """
  Set initial navigation cache. Called on startup
  """
  @spec set :: {:error, boolean} | {:ok, boolean}
  def set do
    menu_map = get_menu_map()
    Cachex.put(:cache, :navigation, menu_map)
  end

  @doc """
  Update navigation cache
  """
  @spec update({:ok, any()} | {:error, changeset}) ::
          {:ok, map()} | {:error, changeset}
  def update({:ok, menu}) do
    menu_map = get_menu_map()
    Cachex.update(:cache, :navigation, menu_map)
    {:ok, menu}
  end

  def update({:error, changeset}), do: {:error, changeset}

  defp get_menu_map do
    {:ok, menus} = Navigation.list_menus()
    for menu <- menus, into: %{}, do: {"#{menu.key}.#{menu.language}", menu}
  end
end

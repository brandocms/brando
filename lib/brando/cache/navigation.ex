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

      get("main.en")
  """
  @spec get(binary) :: map()
  def get(path) do
    [key, lang] = String.split(path, ".")
    get(key, lang)
  end

  @doc """
  Get menu from cache by key and language

      get("main", "en")
  """
  @spec get(binary, binary) :: map()
  def get(key, lang), do: get_in(get(), [key, lang])

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

    Enum.reduce(menus, %{}, fn menu, acc ->
      if Map.has_key?(acc, menu.key) do
        put_in(acc, [menu.key, menu.language], menu)
      else
        Map.put(acc, menu.key, %{menu.language => menu})
      end
    end)
  end
end

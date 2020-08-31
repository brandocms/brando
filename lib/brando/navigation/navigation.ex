defmodule Brando.Navigation do
  @moduledoc """
  Dynamic navigation
  """
  use Brando.Web, :context
  use Brando.Query

  alias Brando.Navigation.Menu
  alias Brando.Navigation.Item
  alias Brando.Users.User

  import Ecto.Query

  @type id :: binary | integer
  @type changeset :: Ecto.Changeset.t()
  @type menu :: Brando.Navigation.Menu.t()
  @type item :: Brando.Navigation.Item.t()
  @type user :: Brando.Users.User.t() | :system
  @type params :: map

  @doc """
  Dataloader initializer
  """
  def data(_) do
    Dataloader.Ecto.new(
      Brando.repo(),
      query: &query/2
    )
  end

  @doc """
  Dataloader queries
  """
  def query(Item = query, _) do
    query
    |> order_by([t], asc: t.sequence)
  end

  def query(queryable, _), do: queryable

  query :list, Menu do
    fn query -> from(q in query) end
  end

  filters Menu do
    fn {:title, title}, query ->
      from q in query, where: ilike(q.title, ^"%#{title}%")
    end
  end

  @doc """
  Create new menu
  """
  @spec create_menu(params, user) :: any
  def create_menu(params, user) do
    %Menu{}
    |> Menu.changeset(params, user)
    |> Brando.repo().insert
  end

  @doc """
  Update menu
  """
  def update_menu(menu_id, params, user) do
    menu_id = (is_binary(menu_id) && String.to_integer(menu_id)) || menu_id
    {:ok, menu} = get_menu(menu_id)

    menu
    |> Menu.changeset(params, user)
    |> Brando.repo().update
  end

  @doc """
  Delete menu
  """
  def delete_menu(menu_id) do
    menu_id =
      if is_binary(menu_id) do
        String.to_integer(menu_id)
      else
        menu_id
      end

    {:ok, menu} = get_menu(menu_id)
    Brando.repo().delete!(menu)
    {:ok, menu}
  end

  @doc """
  Duplicate menu
  """
  def duplicate_menu(menu_id) do
    menu_id = (is_binary(menu_id) && String.to_integer(menu_id)) || menu_id
    {:ok, menu} = get_menu(menu_id)

    menu = Map.merge(menu, %{key: "#{menu.key}_kopi", title: "#{menu.title} (kopi)"})
    menu = Map.delete(menu, [:id, :children, :parent])
    menu = Map.from_struct(menu)

    create_menu(menu, %Brando.Users.User{id: menu.creator_id})
  end

  def get_menu(id) do
    query =
      from t in Menu,
        where: t.id == ^id and is_nil(t.deleted_at),
        preload: [items: ^build_items_query()]

    case Brando.repo().one(query) do
      nil -> {:error, {:menu, :not_found}}
      menu -> {:ok, menu}
    end
  end

  @doc """
  List all menu items
  """
  def list_items do
    items =
      Item
      |> order_by([p], asc: p.parent_key, asc: p.sequence, asc: p.language)
      |> Brando.repo().all()

    {:ok, items}
  end

  @doc """
  Get menu item
  """
  @spec get_item(binary | integer) ::
          {:error, {:item, :not_found}} | {:ok, item}
  def get_item(key) when is_binary(key) do
    query = from t in Item, where: t.key == ^key and is_nil(t.deleted_at)

    case Brando.repo().one(query) do
      nil -> {:error, {:item, :not_found}}
      item -> {:ok, item}
    end
  end

  def get_item(id) do
    query = from t in Item, where: t.id == ^id and is_nil(t.deleted_at)

    case Brando.repo().one(query) do
      nil -> {:error, {:item, :not_found}}
      menu -> {:ok, menu}
    end
  end

  @spec get_item(any, any, any) ::
          {:error, {:item, :not_found}} | {:ok, item}
  def get_item(parent_key, key, language \\ nil) do
    language = language || Brando.config(:default_language)

    query =
      from p in Item,
        where:
          p.parent_key == ^parent_key and
            p.key == ^key and
            p.language == ^language and
            is_nil(p.deleted_at)

    case Brando.repo().one(query) do
      nil -> {:error, {:item, :not_found}}
      item -> {:ok, item}
    end
  end

  @doc """
  Get set of items by parent key
  """
  def list_items(parent_key) do
    items =
      Item
      |> where([p], p.parent_key == ^parent_key)
      |> order_by([p], asc: p.parent_key, asc: p.sequence, asc: p.language)
      |> Brando.repo().all

    {:ok, items}
  end

  @doc """
  Get set of items by parent key and language
  """
  def list_items(parent_key, language) do
    items =
      Item
      |> where([p], p.parent_key == ^parent_key)
      |> where([p], p.language == ^language)
      |> order_by([p], asc: p.parent_key, asc: p.sequence)
      |> Brando.repo().all

    {:ok, items}
  end

  @doc """
  Create new menu item
  """
  @spec create_item(any, any) :: {:ok, item} | {:error, changeset}
  def create_item(params, user) do
    %Item{}
    |> Item.changeset(params, user)
    |> Brando.repo().insert()
  end

  @doc """
  Update menu item
  """
  @spec update_item(id, params, user) :: any
  def update_item(item_id, params, user) do
    item_id = (is_binary(item_id) && String.to_integer(item_id)) || item_id

    {:ok, item} = get_item(item_id)

    case item
         |> Item.changeset(params, user)
         |> Brando.repo().update do
      {:ok, item} ->
        {:ok, item}

      err ->
        err
    end
  end

  @doc """
  Delete item
  """
  @spec delete_item(id) :: {:ok, item}
  def delete_item(item_id) do
    {:ok, item} = get_item(item_id)
    Brando.repo().delete(item)
  end

  @doc """
  Duplicate menu item
  """
  @spec duplicate_item(id) ::
          {:ok, map} | {:error, {:item, :not_found}} | {:error, changeset}
  def duplicate_item(item_id) do
    item_id = (is_binary(item_id) && String.to_integer(item_id)) || item_id

    with {:ok, item} <- get_item(item_id) do
      item
      |> Map.merge(%{key: "#{item.key}_kopi"})
      |> Map.delete([:id, :parent])
      |> Map.from_struct()
      |> create_item(%User{id: item.creator_id})
    end
  end

  defp build_items_query do
    from f in Item,
      where: is_nil(f.deleted_at),
      order_by: [asc: f.sequence, asc: f.key]
  end
end

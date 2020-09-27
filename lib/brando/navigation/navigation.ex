defmodule Brando.Navigation do
  @moduledoc """
  Dynamic navigation

  ## Usage in .eex

  First grab the menu in your controller:

      {:ok, menu} = Brando.Navigation.get_menu("main_menu", "en")

  Then in your template:

      <nav>
        <ul>
        <%= for item <- @menu.items do %>
          <li>
            <a href="<%= item.url %>">
              <%= item.title %>
            </a>
          </li>
        <% end %>
        </ul>
      </nav>

  """
  use Brando.Web, :context
  use Brando.Query

  alias Brando.Navigation.Menu
  alias Brando.Navigation.Item

  import Ecto.Query

  @type id :: binary | integer
  @type params :: map
  @type changeset :: Ecto.Changeset.t()
  @type menu :: Brando.Navigation.Menu.t()
  @type item :: Brando.Navigation.Item.t()
  @type user :: Brando.Users.User.t() | :system

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
        where: t.id == ^id

    case Brando.repo().one(query) do
      nil -> {:error, {:menu, :not_found}}
      menu -> {:ok, menu}
    end
  end

  @doc """
  Get menu.

  !TODO: Try cache first
  """
  @spec get_menu(binary, binary) :: {:error, {:menu, :not_found}} | {:ok, menu}
  def get_menu(key, lang) when is_binary(key) do
    q =
      from p in Menu,
        where: p.key == ^key and p.language == ^lang

    case Brando.repo().one(q) do
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
      |> order_by([p], asc: p.menu_id, asc: p.sequence)
      |> Brando.repo().all()

    {:ok, items}
  end

  @doc """
  Get menu item
  """
  @spec get_item(binary | integer) ::
          {:error, {:item, :not_found}} | {:ok, item}
  def get_item(key) when is_binary(key) do
    query = from t in Item, where: t.key == ^key

    case Brando.repo().one(query) do
      nil -> {:error, {:item, :not_found}}
      item -> {:ok, item}
    end
  end

  def get_item(id) do
    query = from t in Item, where: t.id == ^id

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
            p.language == ^language

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
end

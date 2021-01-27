defmodule Brando.Navigation do
  @moduledoc """
  Dynamic navigation

  ## Usage in .eex

  First get the menu through the navigation plug in your controller:

      defmodule MyController do
        plug Brando.Plug.Navigation, "main"
        # ...

  Then your "main" menu will be available as `@navigation`

  In your template:

      <nav>
        <ul>
        <%= for item <- @navigation.items do %>
          <li>
            <a href="<%= item.url %>">
              <%= item.title %>
            </a>
          </li>
        <% end %>
        </ul>
      </nav>


  If used in a Villain/Liquid template:

      {% for item in navigation.main.en.items %}
        {{ item.url }}
      {% endfor %}

  """
  use Brando.Web, :context
  use Brando.Query

  alias Brando.Cache
  alias Brando.Navigation.Menu
  alias Brando.Villain

  import Ecto.Query

  @type id :: binary | integer
  @type params :: map
  @type changeset :: Ecto.Changeset.t()
  @type menu :: Brando.Navigation.Menu.t()
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
  def query(Item = query, _), do: order_by(query, [t], asc: t.sequence)
  def query(queryable, _), do: queryable

  query :list, Menu, do: fn query -> from(q in query) end

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
    |> Cache.Navigation.update()
    |> update_villains_referencing_navigation()
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
    |> Cache.Navigation.update()
    |> update_villains_referencing_navigation()
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
    update_villains_referencing_navigation({:ok, menu})
  end

  @doc """
  Duplicate menu
  """
  def duplicate_menu(menu_id) do
    menu_id = (is_binary(menu_id) && String.to_integer(menu_id)) || menu_id
    {:ok, menu} = get_menu(menu_id)

    menu =
      menu
      |> Map.merge(%{key: "#{menu.key}_kopi", title: "#{menu.title} (kopi)"})
      |> Map.delete([:id, :children, :parent])
      |> ensure_nested_map()

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
  """
  @spec get_menu(binary, binary) :: {:error, {:menu, :not_found}} | {:ok, menu}
  def get_menu(key, lang) when is_binary(key) do
    case Cache.Navigation.get(key, lang) do
      nil -> {:error, {:menu, :not_found}}
      menu -> {:ok, menu}
    end
  end

  @spec get :: map | nil
  def get do
    Brando.Cache.Navigation.get()
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
  Check all fields for references to GLOBAL
  Rerender if found.
  """
  @spec update_villains_referencing_navigation({:ok, menu} | {:error, changeset}) ::
          {:ok, menu} | {:error, changeset}
  def update_villains_referencing_navigation({:error, changeset}), do: {:error, changeset}

  def update_villains_referencing_navigation({:ok, menu}) do
    search_terms = [
      navigation_vars: "{{ navigation\.(.*?) }}",
      navigation_for_loops: "{% for (.*?) in navigation\.(.*?) %}"
    ]

    villains = Villain.list_villains()
    Villain.rerender_matching_villains(villains, search_terms)
    Villain.rerender_matching_modules(villains, search_terms)

    {:ok, menu}
  end

  defp do_sample(_key, value), do: ensure_nested_map(value)
  defp ensure_nested_map(list) when is_list(list), do: Enum.map(list, &ensure_nested_map/1)

  defp ensure_nested_map(%{__struct__: _} = struct) do
    map = Map.from_struct(struct)
    :maps.map(&do_sample/2, map)
  end

  defp ensure_nested_map(data), do: data
end

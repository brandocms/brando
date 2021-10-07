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
  use BrandoAdmin, :context
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

  query :list, Menu, do: fn query -> from(q in query) end

  filters Menu do
    fn
      {:title, title}, query ->
        from q in query, where: ilike(q.title, ^"%#{title}%")

      {:language, language}, query ->
        from q in query, where: q.language == ^language
    end
  end

  query :single, Menu, do: fn query -> from(q in query) end

  matches Menu do
    fn
      {:id, id}, query ->
        from(t in query, where: t.id == ^id)
    end
  end

  mutation :create, Menu do
    fn entry ->
      {:ok, entry}
      |> Cache.Navigation.update()
      |> update_villains_referencing_navigation()
    end
  end

  mutation :update, Menu do
    fn entry ->
      {:ok, entry}
      |> Cache.Navigation.update()
      |> update_villains_referencing_navigation()
    end
  end

  mutation :delete, Menu do
    fn entry ->
      {:ok, entry}
      |> Cache.Navigation.update()
      |> update_villains_referencing_navigation()
    end
  end

  mutation :duplicate, {Menu, change_fields: [:key, :title]}

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
end

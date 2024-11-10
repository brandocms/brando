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
  import Brando.Query
  import Ecto.Query

  alias Brando.Cache
  alias Brando.Navigation.Item
  alias Brando.Navigation.Menu
  alias Brando.Villain

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

  mutation :duplicate,
           {Menu,
            preload: Menu.preloads_for(),
            change_fields: [
              :key,
              :title,
              {:items, fn _entry, current_items -> fix_items(current_items) end}
            ]}

  defp fix_items(items) do
    Enum.map(items, fn item ->
      %Item{
        item
        | id: nil,
          link: %Brando.Content.Var{
            item.link
            | id: nil
          }
      }
    end)
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

  mutation :create, Item do
    fn entry ->
      {:ok, entry}
      |> Cache.Navigation.update()
      |> update_villains_referencing_navigation()
    end
  end

  mutation :update, Item do
    fn entry ->
      {:ok, entry}
      |> Cache.Navigation.update()
      |> update_villains_referencing_navigation()
    end
  end

  mutation :delete, Item do
    fn entry ->
      {:ok, entry}
      |> Cache.Navigation.update()
      |> update_villains_referencing_navigation()
    end
  end

  query :single, Item, do: fn query -> from(q in query, preload: [link: :identifier]) end

  matches Item do
    fn
      {:id, id}, query ->
        from(t in query, where: t.id == ^id)
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

    # Check for instances in blocks (refs/vars)
    Villain.render_entries_matching_regex(search_terms)

    # Check for instances in modules (this handles the `code` portion of the module's template)
    Villain.rerender_matching_modules(search_terms)

    {:ok, menu}
  end
end

defmodule Brando.Pages do
  @moduledoc """
  Context for pages
  """
  use Brando.Web, :context
  use Brando.Query

  alias Brando.Pages.Page
  alias Brando.Pages.PageFragment
  alias Brando.Pages.Property
  alias Brando.Users.User
  alias Brando.Villain
  alias Ecto.Changeset

  import Ecto.Query

  @type changeset :: Changeset.t()
  @type fragment :: PageFragment.t()
  @type fragment_error :: {:error, {:page_fragment, :not_found}} | {:error, changeset}
  @type id :: binary | integer
  @type page :: Page.t()
  @type params :: map
  @type user :: User.t() | :system

  defmacro __using__(_) do
    quote do
      import Brando.Pages, only: [get_page_fragments: 1, render_fragment: 2, get_fragments: 1]
    end
  end

  @doc """
  Dataloader initializer
  """
  def data(_) do
    Dataloader.Ecto.new(
      Brando.repo(),
      query: &dataloader_query/2
    )
  end

  @doc """
  Dataloader queries
  """
  def dataloader_query(PageFragment = query, _) do
    query
    |> where([f], is_nil(f.deleted_at))
    |> order_by([f], asc: f.sequence, asc: fragment("lower(?)", f.key))
  end

  def dataloader_query(Page = query, _) do
    where(query, [f], is_nil(f.deleted_at))
  end

  def dataloader_query(queryable, _) do
    queryable
  end

  query :list, Page do
    fn
      query ->
        from q in query,
          where: is_nil(q.deleted_at)
    end
  end

  filters Page do
    fn
      {:title, title}, query -> from q in query, where: ilike(q.title, ^"%#{title}%")
      {:parents, true}, query -> from q in query, where: is_nil(q.parent_id)
    end
  end

  query :single, Page,
    do: fn query -> from q in query, where: is_nil(q.deleted_at), preload: [:properties] end

  matches Page do
    fn
      {:id, id}, query ->
        from t in query, where: t.id == ^id

      {:language, language}, query ->
        from t in query,
          where: t.language == ^language

      {:key, key}, query ->
        from t in query,
          where: t.uri == ^key,
          preload: [fragments: ^build_fragments_query()]

      {:path, path}, query when is_list(path) ->
        from t in query,
          where: t.uri == ^Path.join(path),
          preload: [fragments: ^build_fragments_query()]

      {:path, path}, query ->
        from t in query,
          where: t.uri == ^path,
          preload: [fragments: ^build_fragments_query()]

      {:uri, uri}, query when is_list(uri) ->
        from t in query,
          where: t.uri == ^Path.join(uri),
          preload: [fragments: ^build_fragments_query()]

      {:uri, uri}, query ->
        from t in query,
          where: t.uri == ^uri,
          preload: [fragments: ^build_fragments_query()]
    end
  end

  mutation :create, Page
  mutation :update, Page
  mutation :delete, Page
  mutation :duplicate, {Page, delete_fields: [:children, :parent], change_fields: [:uri, :title]}

  @doc """
  Only gets schemas that are parents
  """
  def only_parents(query), do: from(m in query, where: is_nil(m.parent_id))

  @doc """
  List page parents
  """
  def list_parents do
    no_value = %{value: nil, name: "–"}

    parents =
      Page
      |> only_parents()
      |> exclude_deleted()
      |> Brando.repo().all

    val =
      if parents do
        parents
        |> Enum.reverse()
        |> Enum.reduce([no_value], fn parent, acc ->
          acc ++ [%{value: parent.id, name: "#{parent.uri} (#{parent.language})"}]
        end)
      else
        [no_value]
      end

    {:ok, val}
  end

  @doc """
  List available page eex templates
  """
  def list_templates do
    view_module = Brando.web_module(PageView)
    {_, _, templates} = view_module.__templates__

    main_templates =
      templates
      |> Enum.filter(&(not String.starts_with?(&1, "_")))
      |> Enum.map(&%{name: Path.rootname(&1), value: &1})

    {:ok, main_templates}
  end

  @doc """
  Re-render page
  """
  def rerender_page(page_id) do
    {:ok, page} = get_page(%{matches: %{id: page_id}})

    page
    |> Changeset.change()
    |> Villain.rerender_html()
  end

  @doc """
  Rerender all pages
  """
  def rerender_pages do
    {:ok, pages} = list_pages()

    for page <- pages do
      Villain.rerender_html(Changeset.change(page))
    end
  end

  query :list, PageFragment do
    fn query ->
      from q in query,
        where: is_nil(q.deleted_at),
        order_by: [asc: q.parent_key, asc: q.sequence, asc: q.language]
    end
  end

  filters PageFragment do
    fn
      {:title, title}, query ->
        from q in query, where: ilike(q.title, ^"%#{title}%")

      {:language, language}, query ->
        from q in query, where: q.language == ^language

      {:parent_key, parent_key}, query ->
        from q in query, where: q.parent_key == ^parent_key
    end
  end

  query :single, PageFragment, do: fn query -> from q in query, where: is_nil(q.deleted_at) end

  matches PageFragment do
    fn
      {:id, id}, query ->
        from t in query, where: t.id == ^id

      {:language, language}, query ->
        from t in query,
          where: t.language == ^language

      {:key, key}, query ->
        from t in query,
          where: t.key == ^key

      {:parent_key, parent_key}, query ->
        from t in query,
          where: t.parent_key == ^parent_key
    end
  end

  mutation :create, PageFragment

  mutation :update, PageFragment do
    fn entry ->
      update_villains_referencing_fragment(entry)
      {:ok, entry}
    end
  end

  mutation :delete, PageFragment
  mutation :duplicate, {PageFragment, delete_fields: [:parent], change_fields: [:key]}

  @doc """
  Get set of fragments by parent key
  """
  def get_fragments(parent_key) when is_binary(parent_key) do
    require Logger
    IO.warn("get_fragments(binary) is deprecated! Use `get_fragments(map)` instead")
    get_fragments(%{filter: %{parent_key: parent_key}})
  end

  def get_fragments(opts) do
    {:ok, fragments} = list_page_fragments(opts)
    {:ok, Enum.reduce(fragments, %{}, fn x, acc -> Map.put(acc, x.key, x) end)}
  end

  @doc """
  Get fragment from page
  """
  def get_fragment(%Page{fragments: %Ecto.Association.NotLoaded{}} = page, key) do
    page = Brando.repo().preload(page, [:fragments])
    Enum.find(page.fragments, &(&1.key == key))
  end

  def get_fragment(%Page{fragments: fragments}, key) do
    Enum.find(fragments, &(&1.key == key))
  end

  @doc """
  Rerender all fragments
  """
  def rerender_fragments do
    {:ok, fragments} = list_page_fragments()

    for fragment <- fragments do
      Villain.rerender_html(Changeset.change(fragment))
    end
  end

  def rerender_fragment(id) do
    {:ok, fragment} = get_page_fragment(id)
    changeset = Changeset.change(fragment)
    Villain.rerender_html(changeset)
  end

  @deprecated "use list_fragment_translations/2 instead. Now takes `:excluded_language` as Keyword opt"
  def list_page_fragments_translations(
        _,
        _
      ) do
    raise "deprecated!"
  end

  def list_fragments_translations(parent_key, opts \\ []) do
    exclude_lang = Keyword.get(opts, :exclude_language)

    query =
      PageFragment
      |> where([p], p.parent_key == ^parent_key)
      |> exclude_deleted()
      |> order_by([p], [:sequence, :key])

    query =
      if exclude_lang do
        where(query, [p], p.language != ^exclude_lang)
      else
        query
      end

    fragments = Brando.repo().all(query)

    # group keys as "key -> [fragment, fragment2]
    split_fragments = Brando.Utils.split_by(fragments, :key)
    {:ok, split_fragments}
  end

  @doc """
  Get set of fragments by parent key and language
  """
  def get_page_fragments(parent_key, language) do
    fragments =
      PageFragment
      |> where([p], p.parent_key == ^parent_key)
      |> where([p], p.language == ^language)
      |> exclude_deleted()
      |> Brando.repo().all

    Enum.reduce(fragments, %{}, fn x, acc -> Map.put(acc, x.key, x) end)
  end

  @doc """
  Get a property from Page.

  Returns the rendered value of the property.
  """
  @spec get_prop(page, binary) :: any
  def get_prop(%Page{properties: []}, _), do: nil

  def get_prop(%Page{properties: properties}, property) do
    case Enum.find(properties, &(&1.key == property)) do
      nil -> nil
      prop -> render_prop(prop)
    end
  end

  @doc """
  Checks if page has property
  """
  @spec has_prop?(page, binary) :: boolean
  def has_prop?(%Page{properties: []}, _), do: nil

  def has_prop?(%Page{properties: properties}, property) do
    case Enum.find(properties, &(&1.key == property)) do
      nil -> false
      _ -> true
    end
  end

  def render_prop(%Property{type: "text", data: data}), do: Map.get(data, "value", "")
  def render_prop(%Property{type: "boolean", data: data}), do: Map.get(data, "value", false)
  def render_prop(%Property{type: "html", data: data}), do: Map.get(data, "value", "")
  def render_prop(%Property{type: "color", data: data}), do: Map.get(data, "value", "")

  @doc """
  Check all fields for references to `fragment`.
  Rerender if found.
  """
  @spec update_villains_referencing_fragment(fragment) :: [any]
  def update_villains_referencing_fragment(fragment) do
    search_term = [
      fragment: "{% fragment #{fragment.parent_key} #{fragment.key} #{fragment.language} %}"
    ]

    villains = Villain.list_villains()
    Villain.rerender_matching_villains(villains, search_term)
  end

  @doc """
  Fetch a page fragment by `key`.

  ## Example:

      fetch_fragment("my/fragment", Gettext.get_locale(MyApp.Gettext)
      fetch_fragment("my/fragment", "en")

  If no language is passed, default language set in `brando.exs` will be used.
  If the fragment isn't found, it will render an error box.
  """
  def fetch_fragment(key, language \\ nil) when is_binary(key) do
    language = language || Brando.config(:default_language)

    fragment =
      Brando.repo().one(
        from p in PageFragment,
          where: p.key == ^key and p.language == ^language and is_nil(p.deleted_at)
      )

    case fragment do
      nil ->
        ~s(<div class="page-fragment-missing">
             <strong>Missing page fragment</strong> <br />
             key..: #{key}<br />
             lang.: #{language}
           </div>) |> Phoenix.HTML.raw()

      fragment ->
        Phoenix.HTML.raw(fragment.html)
    end
  end

  def render_fragment(%PageFragment{} = fragment), do: Phoenix.HTML.raw(fragment.html)

  def render_fragment(fragments, key) when is_map(fragments) do
    case Map.get(fragments, key) do
      nil ->
        ~s(<div class="page-fragment-missing text-mono">
             <strong>Missing page fragment</strong> <br />
             key...: #{key}<br />
             frags.: #{inspect(Map.keys(fragments))}
           </div>) |> Phoenix.HTML.raw()

      fragment ->
        Phoenix.HTML.raw(fragment.html)
    end
  end

  def render_fragment(parent, key, language \\ nil) when is_binary(parent) and is_binary(key) do
    opts = %{matches: %{parent_key: parent, key: key}}
    opts = (language && put_in(opts.matches, :language, language)) || opts

    case get_page_fragment(opts) do
      {:error, {:page_fragment, :not_found}} ->
        ~s(<div class="page-fragment-missing">
             <strong>Missing page fragment</strong> <br />
             parent: #{parent}<br />
             key...: #{key}<br />
             lang..: #{language}
           </div>) |> Phoenix.HTML.raw()

      {:ok, fragment} ->
        Phoenix.HTML.raw(fragment.html)
    end
  end

  defp build_fragments_query do
    from f in PageFragment,
      where: is_nil(f.deleted_at),
      order_by: [asc: f.sequence, asc: f.key]
  end
end

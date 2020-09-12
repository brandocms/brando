defmodule Brando.Pages do
  @moduledoc """
  Context for pages
  """
  use Brando.Web, :context
  use Brando.Query

  alias Brando.Pages.Page
  alias Brando.Pages.PageFragment
  alias Brando.Users.User
  alias Brando.Villain

  import Ecto.Query

  @type changeset :: Ecto.Changeset.t()
  @type fragment :: Brando.Pages.PageFragment.t()
  @type id :: binary | integer
  @type page :: Brando.Pages.Page.t()
  @type params :: map
  @type user :: Brando.Users.User.t() | :system

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
      query: &query/2
    )
  end

  @doc """
  Dataloader queries
  """
  def query(PageFragment = query, _) do
    query
    |> where([f], is_nil(f.deleted_at))
    |> order_by([f], asc: f.sequence, asc: fragment("lower(?)", f.key))
  end

  def query(queryable, _), do: queryable

  query :list, Page do
    fn
      query ->
        from q in query,
          where: is_nil(q.deleted_at),
          where: is_nil(q.parent_id)
    end
  end

  filters Page do
    fn {:title, title}, query ->
      from q in query, where: ilike(q.title, ^"%#{title}%")
    end
  end

  query :single, Page, do: fn query -> from q in query, where: is_nil(q.deleted_at) end

  matches Page do
    fn
      {:id, id}, query ->
        from t in query, where: t.id == ^id

      {:language, language}, query ->
        from t in query,
          where: t.language == ^language

      {:key, key}, query ->
        from t in query,
          where: t.key == ^key,
          preload: [fragments: ^build_fragments_query()]

      {:path, path}, query when is_list(path) ->
        from t in query,
          where: t.key == ^Path.join(path),
          preload: [fragments: ^build_fragments_query()]

      {:path, path}, query ->
        from t in query,
          where: t.key == ^path,
          preload: [fragments: ^build_fragments_query()]
    end
  end

  @doc """
  Create new page
  """
  @spec create_page(params, user) :: any
  def create_page(params, user) do
    %Page{}
    |> Page.changeset(params, user)
    |> Brando.repo().insert
  end

  @doc """
  Update page
  """
  def update_page(page_id, params, user) do
    page_id = (is_binary(page_id) && String.to_integer(page_id)) || page_id
    {:ok, page} = get_page(page_id)

    page
    |> Page.changeset(params, user)
    |> Brando.repo().update
  end

  @doc """
  Delete page
  """
  def delete_page(page_id) do
    page_id =
      if is_binary(page_id) do
        String.to_integer(page_id)
      else
        page_id
      end

    {:ok, page} = get_page(page_id)
    Brando.repo().soft_delete!(page)
    {:ok, page}
  end

  @doc """
  Duplicate page
  """
  def duplicate_page(page_id) do
    page_id = (is_binary(page_id) && String.to_integer(page_id)) || page_id
    {:ok, page} = get_page(page_id)

    page = Map.merge(page, %{key: "#{page.key}_kopi", title: "#{page.title} (kopi)"})
    page = Map.delete(page, [:id, :children, :parent])
    page = Map.from_struct(page)

    create_page(page, %Brando.Users.User{id: page.creator_id})
  end

  @doc """
  Only gets schemas that are parents
  """
  def only_parents(query) do
    from m in query,
      where: is_nil(m.parent_id)
  end

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
          acc ++ [%{value: parent.id, name: "#{parent.key} (#{parent.language})"}]
        end)
      else
        [no_value]
      end

    {:ok, val}
  end

  @doc """
  List available page templates
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
  def rerender_page(id) do
    {:ok, page} = get_page(id)
    changeset = Ecto.Changeset.change(page)
    Brando.Villain.rerender_html(changeset)
  end

  @doc """
  Rerender all pages
  """
  def rerender_pages do
    {:ok, pages} = list_pages()

    for page <- pages do
      Brando.Villain.rerender_html(Ecto.Changeset.change(page))
    end
  end

  @doc """
  Rerender all fragments
  """
  def rerender_fragments do
    {:ok, fragments} = list_page_fragments()

    for fragment <- fragments do
      Brando.Villain.rerender_html(Ecto.Changeset.change(fragment))
    end
  end

  def rerender_fragment(id) do
    {:ok, fragment} = get_page_fragment(id)
    changeset = Ecto.Changeset.change(fragment)
    Brando.Villain.rerender_html(changeset)
  end

  @doc """
  List all page fragments
  """
  def list_page_fragments do
    fragments =
      PageFragment
      |> order_by([p], asc: p.parent_key, asc: p.sequence, asc: p.language)
      |> exclude_deleted()
      |> Brando.repo().all()

    {:ok, fragments}
  end

  @doc """
  Get page fragment
  """
  @spec get_page_fragment(binary | integer) ::
          {:error, {:page_fragment, :not_found}} | {:ok, fragment}
  def get_page_fragment(key) when is_binary(key) do
    query = from t in PageFragment, where: t.key == ^key and is_nil(t.deleted_at)

    case Brando.repo().one(query) do
      nil -> {:error, {:page_fragment, :not_found}}
      fragment -> {:ok, fragment}
    end
  end

  def get_page_fragment(id) do
    query = from t in PageFragment, where: t.id == ^id and is_nil(t.deleted_at)

    case Brando.repo().one(query) do
      nil -> {:error, {:page_fragment, :not_found}}
      page -> {:ok, page}
    end
  end

  @spec get_page_fragment(any, any, any) ::
          {:error, {:page_fragment, :not_found}} | {:ok, fragment}
  def get_page_fragment(parent_key, key, language \\ nil) do
    language = language || Brando.config(:default_language)

    query =
      from p in PageFragment,
        where:
          p.parent_key == ^parent_key and
            p.key == ^key and
            p.language == ^language and
            is_nil(p.deleted_at)

    case Brando.repo().one(query) do
      nil -> {:error, {:page_fragment, :not_found}}
      fragment -> {:ok, fragment}
    end
  end

  @doc """
  Get set of fragments by parent key
  """
  @deprecated "Use `{:ok, fragments} = get_fragments(parent_key)` instead"
  def get_page_fragments(parent_key) do
    {:ok, fragments} = list_page_fragments(parent_key)
    Enum.reduce(fragments, %{}, fn x, acc -> Map.put(acc, x.key, x) end)
  end

  @doc """
  Get set of fragments by parent key
  """
  def get_fragments(parent_key) do
    {:ok, fragments} = list_page_fragments(parent_key)
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
  Get set of fragments by parent key
  """
  def list_page_fragments(parent_key) do
    fragments =
      PageFragment
      |> where([p], p.parent_key == ^parent_key)
      |> exclude_deleted()
      |> order_by([p], asc: p.parent_key, asc: p.sequence, asc: p.language)
      |> Brando.repo().all

    {:ok, fragments}
  end

  @doc """
  Get set of fragments by parent key and language
  """
  def list_page_fragments(parent_key, language) do
    fragments =
      PageFragment
      |> where([p], p.parent_key == ^parent_key)
      |> where([p], p.language == ^language)
      |> exclude_deleted()
      |> order_by([p], asc: p.parent_key, asc: p.sequence)
      |> Brando.repo().all

    {:ok, fragments}
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
  Create new page fragment
  """
  @spec create_page_fragment(any, any) :: {:ok, fragment} | {:error, changeset}
  def create_page_fragment(params, user) do
    %PageFragment{}
    |> PageFragment.changeset(params, user)
    |> Brando.repo().insert()
  end

  @doc """
  Update page fragment
  """
  @spec update_page_fragment(id, params, user) :: any
  def update_page_fragment(page_fragment_id, params, user) do
    page_fragment_id =
      (is_binary(page_fragment_id) && String.to_integer(page_fragment_id)) || page_fragment_id

    {:ok, page_fragment} = get_page_fragment(page_fragment_id)

    case page_fragment
         |> PageFragment.changeset(params, user)
         |> Brando.repo().update do
      {:ok, page_fragment} ->
        update_villains_referencing_fragment(page_fragment)
        {:ok, page_fragment}

      err ->
        err
    end
  end

  @doc """
  Delete page_fragment
  """
  @spec delete_page_fragment(id) :: {:ok, fragment}
  def delete_page_fragment(page_fragment_id) do
    {:ok, page_fragment} = get_page_fragment(page_fragment_id)
    Brando.repo().soft_delete(page_fragment)
  end

  @doc """
  Duplicate page fragment
  """
  @spec duplicate_page_fragment(id) ::
          {:ok, map} | {:error, {:page_fragment, :not_found}} | {:error, changeset}
  def duplicate_page_fragment(fragment_id) do
    fragment_id = (is_binary(fragment_id) && String.to_integer(fragment_id)) || fragment_id

    with {:ok, fragment} <- get_page_fragment(fragment_id) do
      fragment
      |> Map.merge(%{key: "#{fragment.key}_kopi"})
      |> Map.delete([:id, :parent])
      |> Map.from_struct()
      |> create_page_fragment(%User{id: fragment.creator_id})
    end
  end

  @doc """
  Check all fields for references to `fragment`.
  Rerender if found.
  """
  @spec update_villains_referencing_fragment(fragment :: Brando.Pages.PageFragment.t()) :: [any]
  def update_villains_referencing_fragment(fragment) do
    search_term = "${FRAGMENT:#{fragment.parent_key}/#{fragment.key}/#{fragment.language}"
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

  def render_fragment(%PageFragment{} = fragment) do
    Phoenix.HTML.raw(fragment.html)
  end

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
    case get_page_fragment(parent, key, language) do
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

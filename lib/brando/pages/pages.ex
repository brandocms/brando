defmodule Brando.Pages do
  @moduledoc """
  Context for pages
  """
  use Brando.Web, :context

  alias Brando.Pages.Page
  alias Brando.Pages.PageFragment
  alias Brando.Villain

  import Ecto.Query

  defmacro __using__(_) do
    quote do
      import Brando.Pages, only: [get_page_fragments: 1, render_fragment: 2]
    end
  end

  @doc """
  Create new page
  """
  def create_page(params, user) do
    %Page{}
    |> Brando.Utils.Schema.put_creator(user)
    |> Page.changeset(:create, params)
    |> Brando.repo().insert
  end

  @doc """
  Update page
  """
  def update_page(page_id, params) do
    page_id = (is_binary(page_id) && String.to_integer(page_id)) || page_id
    {:ok, page} = get_page(page_id)

    page
    |> Page.changeset(:update, params)
    |> Brando.repo().update
  end

  @doc """
  Delete page
  """
  def delete_page(page_id) do
    page_id = (is_binary(page_id) && String.to_integer(page_id)) || page_id
    {:ok, page} = get_page(page_id)
    Brando.repo().soft_delete!(page)
    {:ok, page}
  end

  @doc """
  Duplicate page
  """
  def duplicate_page(page_id, user) do
    page_id = (is_binary(page_id) && String.to_integer(page_id)) || page_id
    {:ok, page} = get_page(page_id)

    page = Map.merge(page, %{key: "#{page.key}_kopi", title: "#{page.title} (kopi)"})
    page = Map.delete(page, [:id, :children, :creator, :parent])
    page = Map.from_struct(page)

    {:ok, duplicated_page} = create_page(page, user)
    {:ok, Map.merge(duplicated_page, %{parent: nil, children: nil, creator: nil})}
  end

  @doc """
  List all pages
  """
  def list_pages do
    pages =
      Page
      |> Page.only_parents()
      |> order_by([p], asc: p.key)
      |> exclude_deleted()
      |> Brando.repo().all

    {:ok, pages}
  end

  @doc """
  List page parents
  """
  def list_parents do
    no_value = %{value: nil, name: "–"}

    parents =
      Page
      |> Page.only_parents()
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
  Get page
  """
  def get_page(key) when is_binary(key) do
    page = Brando.repo().get_by(Page, key: key, deleted_at: nil)

    case page do
      nil -> {:error, {:page, :not_found}}
      page -> {:ok, Brando.repo().preload(page, :fragments)}
    end
  end

  def get_page(id) do
    page = Brando.repo().get_by(Page, id: id, deleted_at: nil)

    case page do
      nil -> {:error, {:page, :not_found}}
      page -> {:ok, Brando.repo().preload(page, :fragments)}
    end
  end

  @doc """
  Get page by key
  """
  def get_page(key, lang) when is_binary(key) do
    q =
      from p in Page,
        where: p.key == ^key and p.language == ^lang and is_nil(p.deleted_at),
        preload: :fragments

    case Brando.repo().one(q) do
      nil -> {:error, {:page, :not_found}}
      page -> {:ok, page}
    end
  end

  @doc """
  Get page by key
  """
  def get_page_with_children(key, lang) when is_binary(key) do
    q =
      from p in Page,
        join: c in assoc(p, :children),
        where: p.key == ^key and p.language == ^lang and is_nil(p.deleted_at),
        preload: [:children, :fragments]

    case Brando.repo().one(q) do
      nil -> {:error, {:page, :not_found}}
      page -> {:ok, page}
    end
  end

  @doc """
  Get page by parent_key and key
  """
  def get_page(nil, key, lang) when is_binary(key) do
    q =
      from p in Page,
        where: p.key == ^key and p.language == ^lang and is_nil(p.deleted_at),
        preload: [:fragments]

    case Brando.repo().one(q) do
      nil -> {:error, {:page, :not_found}}
      page -> {:ok, page}
    end
  end

  def get_page(parent_key, key, lang) when is_binary(key) do
    q =
      from p in Page,
        left_join: pp in assoc(p, :parent),
        where:
          p.key == ^key and
            pp.key == ^parent_key and
            p.language == ^lang and
            is_nil(p.deleted_at),
        preload: [:fragments]

    case Brando.repo().one(q) do
      nil -> {:error, {:page, :not_found}}
      page -> {:ok, page}
    end
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
      |> order_by([p], asc: p.parent_key, asc: p.key, asc: p.language)
      |> exclude_deleted()
      |> Brando.repo().all()

    {:ok, fragments}
  end

  @doc """
  Get page fragment
  """
  def get_page_fragment(key) when is_binary(key) do
    page = Brando.repo().get_by(PageFragment, key: key, deleted_at: nil)

    case page do
      nil -> {:error, {:page_fragment, :not_found}}
      page -> {:ok, page}
    end
  end

  def get_page_fragment(id) do
    page = Brando.repo().get_by(PageFragment, id: id, deleted_at: nil)

    case page do
      nil -> {:error, {:page_fragment, :not_found}}
      page -> {:ok, page}
    end
  end

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
  def get_page_fragments(parent_key) do
    fragments =
      PageFragment
      |> where([p], p.parent_key == ^parent_key)
      |> exclude_deleted()
      |> Brando.repo().all

    Enum.reduce(fragments, %{}, fn x, acc -> Map.put(acc, x.key, x) end)
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
  def create_page_fragment(params, user) do
    %PageFragment{}
    |> Brando.Utils.Schema.put_creator(user)
    |> PageFragment.changeset(:create, params)
    |> Brando.repo().insert
  end

  @doc """
  Update page fragment
  """
  def update_page_fragment(page_fragment_id, params) do
    page_fragment_id =
      (is_binary(page_fragment_id) && String.to_integer(page_fragment_id)) || page_fragment_id

    {:ok, page_fragment} = get_page_fragment(page_fragment_id)

    case page_fragment |> PageFragment.changeset(:update, params) |> Brando.repo().update do
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
  def delete_page_fragment(page_fragment_id) do
    {:ok, page_fragment} = get_page_fragment(page_fragment_id)
    Brando.repo().soft_delete!(page_fragment)
    {:ok, page_fragment}
  end

  @doc """
  Duplicate page fragment
  """
  def duplicate_page_fragment(fragment_id, user) do
    fragment_id = (is_binary(fragment_id) && String.to_integer(fragment_id)) || fragment_id
    {:ok, fragment} = get_page_fragment(fragment_id)

    {:ok, dup_fragment} =
      fragment
      |> Map.merge(%{key: "#{fragment.key}_kopi"})
      |> Map.delete([:id, :parent])
      |> Map.from_struct()
      |> create_page_fragment(user)

    {:ok, Map.merge(dup_fragment, %{creator: nil})}
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
end

defmodule Brando.Pages do
  @moduledoc """
  Context for pages
  """
  use BrandoAdmin, :context
  use Brando.Query

  alias Brando.Pages.Page
  alias Brando.Pages.Fragment
  alias Brando.Users.User
  alias Brando.Villain
  alias Ecto.Changeset

  import Ecto.Query

  @type changeset :: Changeset.t()
  @type fragment :: Fragment.t()
  @type fragment_error :: {:error, {:fragment, :not_found}} | {:error, changeset}
  @type id :: binary | integer
  @type page :: Page.t()
  @type params :: map
  @type user :: User.t() | :system

  defmacro __using__(_) do
    quote do
      import Brando.Pages, only: [get_fragments: 1, render_fragment: 2, get_fragments: 2]
    end
  end

  query :list, Page do
    fn query -> from(q in query) end
  end

  filters Page do
    fn
      {:has_url, has_url}, query -> from q in query, where: q.has_url == ^has_url
      {:language, language}, query -> from q in query, where: q.language == ^language
      {:uri, uri}, query -> from q in query, where: ilike(q.uri, ^"%#{uri}%")
      {:title, title}, query -> from q in query, where: ilike(q.title, ^"%#{title}%")
      {:parents, true}, query -> from q in query, where: is_nil(q.parent_id)
    end
  end

  query :single, Page,
    do: fn query ->
      from q in query, preload: [:parent, :meta_image]
    end

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

      {:has_url, has_url}, query ->
        from q in query, where: q.has_url == ^has_url
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

    if Code.ensure_loaded?(view_module) do
      {_, _, templates} = view_module.__templates__

      main_templates = Enum.filter(templates, &(not String.starts_with?(&1, "_")))

      {:ok, main_templates}
    else
      html_module = Brando.web_module(PageHTML)

      main_templates =
        :functions
        |> html_module.__info__()
        |> Enum.map(fn {fun, _arity} -> to_string(fun) end)
        |> Enum.reject(&String.starts_with?(&1, "__"))
        |> Enum.map(&(&1 <> ".html"))

      {:ok, main_templates}
    end
  end

  query :list, Fragment do
    fn query ->
      from q in query,
        order_by: [asc: q.parent_key, asc: q.sequence, asc: q.language]
    end
  end

  filters Fragment do
    fn
      {:title, title}, query ->
        from q in query, where: ilike(q.title, ^"%#{title}%")

      {:language, language}, query ->
        from q in query, where: q.language == ^language

      {:parent_key, parent_key}, query ->
        from q in query, where: q.parent_key == ^parent_key
    end
  end

  query :single, Fragment, do: fn query -> from(q in query) end

  matches Fragment do
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

  mutation :create, Fragment

  mutation :update, Fragment do
    fn fragment ->
      Villain.render_entries_with_fragment_id(fragment.id)
      {:ok, fragment}
    end
  end

  mutation :delete, Fragment do
    fn fragment ->
      Villain.render_entries_with_fragment_id(fragment.id)
      {:ok, fragment}
    end
  end

  mutation :duplicate, {Fragment, delete_fields: [], change_fields: [:key]}

  @doc """
  Find fragment with `id` in `fragments`
  """
  def find_fragment(fragments, id) do
    fragments
    |> Enum.find(&(&1.id == id))
    |> case do
      nil -> {:error, {:fragment, :not_found, id}}
      mod -> {:ok, mod}
    end
  end

  @doc """
  Get set of fragments by parent key
  """
  def get_fragments(parent_key) when is_binary(parent_key) do
    require Logger
    IO.warn("get_fragments(binary) is deprecated! Use `get_fragments(map)` instead")
    get_fragments(%{filter: %{parent_key: parent_key}})
  end

  def get_fragments(opts) when is_map(opts) do
    {:ok, fragments} = list_fragments(opts)
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
    {:ok, fragments} = list_fragments()
    Villain.render_entries(Fragment, Enum.map(fragments, & &1.id))
  end

  def rerender_fragment(id) do
    Villain.render_entry(Fragment, id)
  end

  def list_fragments_translations(parent_key, opts \\ []) do
    exclude_lang = Keyword.get(opts, :exclude_language)

    query =
      Fragment
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
  def get_fragments(parent_key, language) do
    fragments =
      Fragment
      |> where([p], p.parent_key == ^parent_key)
      |> where([p], p.language == ^language)
      |> exclude_deleted()
      |> Brando.repo().all

    Enum.reduce(fragments, %{}, fn x, acc -> Map.put(acc, x.key, x) end)
  end

  @doc """
  Get a var from Page.

  Returns the rendered value of the var.
  """
  @spec get_var(page, binary) :: any
  def get_var(%Page{vars: nil}, _), do: nil
  def get_var(%Page{vars: []}, _), do: nil

  def get_var(%Page{vars: vars}, var_key) do
    case Enum.find(vars, &(&1.key == var_key)) do
      nil -> nil
      var -> Brando.Content.render_var(var)
    end
  end

  def get_var(_, _), do: nil

  @doc """
  Checks if page has var
  """
  @spec has_var?(page, binary) :: boolean
  def has_var?(%Page{vars: []}, _), do: nil

  def has_var?(%Page{vars: vars}, var) do
    case Enum.find(vars, &(&1.key == var)) do
      nil -> false
      _ -> true
    end
  end

  @doc """
  Check all fields for references to `fragment`.
  Rerender if found.
  """
  @spec update_villains_referencing_fragment(fragment) :: [any]
  def update_villains_referencing_fragment(fragment) do
    search_term = [
      fragment: "{% fragment #{fragment.parent_key} #{fragment.key} #{fragment.language} %}"
    ]

    # Check for instances in blocks (refs/vars)
    Villain.render_entries_matching_regex(search_term)

    # Check for instances in modules (this handles the `code` portion of the module's template)
    Villain.rerender_matching_modules(search_term)
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
        from p in Fragment,
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
        Phoenix.HTML.raw(fragment.rendered_blocks)
    end
  end

  def render_fragment(%Fragment{} = fragment), do: Phoenix.HTML.raw(fragment.rendered_blocks)

  def render_fragment(fragments, key) when is_map(fragments) do
    case Map.get(fragments, key) do
      nil ->
        ~s(<div class="page-fragment-missing text-mono">
             <strong>Missing page fragment</strong> <br />
             key...: #{key}<br />
             frags.: #{inspect(Map.keys(fragments))}
           </div>) |> Phoenix.HTML.raw()

      fragment ->
        Phoenix.HTML.raw(fragment.rendered_blocks)
    end
  end

  def render_fragment(parent, key, language \\ nil) when is_binary(parent) and is_binary(key) do
    opts = %{matches: %{parent_key: parent, key: key}}
    opts = (language && put_in(opts.matches, :language, language)) || opts

    case get_fragment(opts) do
      {:error, {:fragment, :not_found}} ->
        ~s(<div class="page-fragment-missing">
             <strong>Missing page fragment</strong> <br />
             parent: #{parent}<br />
             key...: #{key}<br />
             lang..: #{language}
           </div>) |> Phoenix.HTML.raw()

      {:ok, fragment} ->
        Phoenix.HTML.raw(fragment.rendered_blocks)
    end
  end

  defp build_fragments_query do
    from f in Fragment,
      where: is_nil(f.deleted_at),
      order_by: [asc: f.sequence, asc: f.key]
  end
end

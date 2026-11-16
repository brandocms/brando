defmodule Brando.Plug.HTML do
  @moduledoc """
  A plug with HTML oriented helpers
  """
  import Plug.Conn

  alias Brando.Blueprint.URL
  alias Brando.JSONLD
  alias Brando.Utils

  require Logger

  @type conn :: Plug.Conn.t()

  @doc """
  A plug for setting `body`'s `data-script` attribute to named section.

  Used for calling javascript setup(). Check the `data-script` attr
  in javascript.

  ## Usage

      import Brando.Plug.HTML
      plug :put_section, "users"
  """

  @spec put_section(conn, atom | binary) :: conn
  def put_section(conn, name) do
    conn
    |> put_private(:brando_section_name, name)
    |> assign(:section, name)
  end

  @spec get_section(conn) :: binary
  def get_section(conn), do: conn.private.brando_section_name

  @doc """
  Add `classes` to body

  ## Usage

      import Brando.Plug.HTML
      plug :put_css_classes, "wrapper box"
  """
  @spec put_css_classes(conn, binary | [binary]) :: conn
  def put_css_classes(conn, classes) when is_binary(classes), do: put_private(conn, :brando_css_classes, classes)

  def put_css_classes(conn, classes) when is_list(classes),
    do: put_private(conn, :brando_css_classes, Enum.join(classes, " "))

  def put_css_classes(conn, _), do: conn

  @doc """
  Adds `title` to `conn`'s assigns as `page_title`
  """
  def put_title(conn, title, opts \\ []) do
    skip_prefix = Keyword.get(opts, :skip_prefix, false)
    skip_postfix = Keyword.get(opts, :skip_postfix, false)

    conn
    |> put_private(:brando_skip_title_prefix, skip_prefix)
    |> put_private(:brando_skip_title_postfix, skip_postfix)
    |> assign(:page_title, title)
  end

  @doc """
  Adds JSON-LD breadcrumbs to conn.

  Accepts either a page struct with pre-computed breadcrumbs, or a list
  of `{name, url}` tuples for manual breadcrumb construction (useful for
  non-page blueprints).

  ## Examples

      # From a page with stored breadcrumbs
      put_breadcrumbs(conn, page)

      # Manual breadcrumbs for other blueprints
      put_breadcrumbs(conn, [{"Home", "/"}, {"Blog", "/blog"}, {"My Post", "/blog/my-post"}])

  """
  def put_breadcrumbs(conn, %{breadcrumbs: breadcrumbs}) when is_list(breadcrumbs) and breadcrumbs != [] do
    tuples = Enum.map(breadcrumbs, fn %{"title" => title, "uri" => uri} -> {title, uri} end)
    put_json_ld(conn, :breadcrumbs, tuples)
  end

  def put_breadcrumbs(conn, breadcrumbs) when is_list(breadcrumbs) do
    put_json_ld(conn, :breadcrumbs, breadcrumbs)
  end

  def put_breadcrumbs(conn, _), do: conn

  @doc """
  Adds JSON-LD structured data to the conn.

  Can be called multiple times to add multiple entities to the `@graph`.

  ## Examples

      # Add breadcrumbs
      put_json_ld(conn, :breadcrumbs, [{"Home", "/"}, {"About", "/about"}])

      # Add a content entity from blueprint DSL
      put_json_ld(conn, MyApp.Blog.Post, post)

      # Add with extra runtime fields
      put_json_ld(conn, MyApp.Blog.Post, post, [%{name: :image, type: :image, value_fn: &get_image/1}])

  Sets the WebPage `@type` for JSON-LD without adding a content entity.

  Useful for list pages or other controllers where you don't have a single
  entity to pass to `put_json_ld/3` but still want to control the page type.

  ## Example

      # In a list controller action
      conn
      |> put_json_ld_type("CollectionPage")
      |> put_breadcrumbs([{"Home", "/"}, {"Blog", "/blog"}])
      |> render(:list)

  """
  def put_json_ld_type(conn, type) when is_binary(type) do
    assign(conn, :json_ld_page_type, type)
  end

  def put_json_ld(conn, :breadcrumbs, breadcrumbs), do: assign(conn, :json_ld_breadcrumbs, breadcrumbs)

  @doc """
  Adds pre-built JSON-LD nodes to the graph.

  `put_json_ld/4` derives a node from an entry through its blueprint's
  `json_ld_schema`. Nodes that describe the business rather than an entry —
  `Service`, `Place`, a hand-built `Event` — have no entry to derive from, so
  build the struct and append it:

      services =
        Brando.JSONLD.Schema.Service.build_all(@services,
          provider: "\#{Brando.Utils.hostname()}/#identity",
          area_served: "Worldwide"
        )

      put_json_ld(conn, :entities, services)

  Appends, so it composes with `put_json_ld/4` in any order.
  """
  def put_json_ld(conn, :entities, entities) do
    existing = Map.get(conn.assigns, :json_ld_entities, [])
    assign(conn, :json_ld_entities, existing ++ List.wrap(entities))
  end

  def put_json_ld(conn, module, data, extra_fields \\ []) do
    language = Map.get(data, :language, conn.assigns.language)
    url = page_url(conn)
    built = module |> build_json_ld(data, language, extra_fields, url) |> List.wrap()
    existing = Map.get(conn.assigns, :json_ld_entities, [])
    entry = %{at: length(existing), built: built, url: url, build: {module, data, language, extra_fields}}

    conn
    |> assign(:json_ld_entities, existing ++ built)
    |> put_private(:brando_json_ld_entries, (conn.private[:brando_json_ld_entries] || []) ++ [entry])
    |> put_json_ld_page(data, List.first(built))
    |> put_page_entry(data)
  end

  defp build_json_ld(module, data, language, extra_fields, url) do
    data = Map.merge(data, %{__meta__: %{current_url: url, language: language}})
    JSONLD.extract_json_ld(module, data, extra_fields)
  end

  @doc """
  The JSON-LD entities added with `put_json_ld/3` and `put_json_ld/4`, in the
  order they were added, at the page's URL (`page_url/1`).

  `conn.assigns.json_ld_entities` holds them as they were built when
  `put_json_ld/3` was called, at the page's URL then. An entry's entity is
  built again here when the page's URL changed after that (`put_hreflang/2`
  or `put_page_url/2` called later), so its `@id` and its fields of type
  `:current_url` name the URL the page has once the controller is done.
  """
  @spec json_ld_entities(conn) :: [struct()]
  def json_ld_entities(conn) do
    url = page_url(conn)
    entities = Map.get(conn.assigns, :json_ld_entities, [])

    # From the last, so a rebuilt entry's place stays where the earlier ones are
    (conn.private[:brando_json_ld_entries] || [])
    |> Enum.reverse()
    |> Enum.reduce(entities, fn %{at: at, built: built, url: built_url, build: build}, entities ->
      if built_url != url and Enum.slice(entities, at, length(built)) == built do
        {module, data, language, extra_fields} = build
        rebuilt = module |> build_json_ld(data, language, extra_fields, url) |> List.wrap()
        Enum.take(entities, at) ++ rebuilt ++ Enum.drop(entities, at + length(built))
      else
        entities
      end
    end)
  end

  @doc false
  # The profile page's main entity (`json_ld_main_entity`) at the page's URL
  # `url`, as `json_ld_entities/1` builds the entry again when that changed
  def json_ld_main_entity(conn, url) do
    id = conn.assigns[:json_ld_main_entity]

    Enum.find_value(conn.private[:brando_json_ld_entries] || [], id, fn
      %{built: [%{"@id": ^id, "@type": type} | _], url: built_url} when is_binary(id) and built_url != url ->
        JSONLD.node_id(url, type |> to_string() |> String.downcase())

      _entry ->
        nil
    end)
  end

  # A person's own page is their profile: a `ProfilePage` about the Person.
  # (An entry with its own `json_ld_type` gives the entity that type instead.)
  defp put_json_ld_page(conn, _data, %{"@type": "Person", "@id": id}) when is_binary(id) do
    conn
    |> assign(:json_ld_page_type, "ProfilePage")
    |> assign(:json_ld_main_entity, id)
  end

  defp put_json_ld_page(conn, data, _entity),
    do: assign(conn, :json_ld_page_type, Map.get(data, :json_ld_type, "WebPage"))

  @doc """
  Put hreflang data in conn

  If you have a translatable entry:

      put_hreflang(conn, entry)

  If you want to supply your own alternates

      put_hreflang(conn, [en: "/en/something", no: "/no/something"])

  Or to run localized_path on all available languages:

      put_hreflang(conn, {:post_path, [conn, :list]})

  This form keeps the alternates as paths, so `Brando.HTML.alternate_url/1`
  links stay on the host the visitor is on; `Brando.HTML.render_hreflangs/1`
  gives the `<link rel="alternate">` tags the site's base URL.

  The head's alternate in the page's own language is the page's URL
  (`page_url/1`), in place of any given for that language: see `hreflangs/1`.
  """
  def put_hreflang(conn, hreflangs) when is_list(hreflangs) do
    alternates = Enum.map(hreflangs, fn {language, path} -> {language, with_host(path)} end)
    put_alternates(conn, alternates)
  end

  def put_hreflang(conn, {fun, args}) do
    alternates =
      Enum.map(Brando.Languages.languages(), fn [value: lang_code, text: _] ->
        {String.to_existing_atom(lang_code), Brando.I18n.Helpers.localized_path(lang_code, fun, args)}
      end)

    put_alternates(conn, alternates)
  end

  def put_hreflang(conn, %{alternate_entries: %Ecto.Association.NotLoaded{}} = entry) do
    Logger.error("""
    ==> put_hreflang: Missing preload for :alternate_entries

    Url....: #{Brando.Utils.hostname(Path.join(["/" | conn.path_info]))}
    Schema.: #{entry.__struct__}
    Id.....: ##{entry.id}

    """)

    conn
  end

  # An entry without a URL of its own (the 404 and 410 pages) gets neither a
  # canonical nor alternates: pointing them at a URL would claim the page is
  # that URL, and a static build serves its 404 page at every missing path.
  # Alternates without a URL of their own are skipped quietly; one that should
  # have a URL but resolves to none is logged, as that is a missing preload.
  def put_hreflang(conn, %{alternate_entries: alternate_entries} = entry) when is_list(alternate_entries) do
    case URL.resolve(entry, :with_host) do
      nil ->
        conn

      canonical_url ->
        hreflangs =
          alternate_entries
          |> Enum.filter(&(Map.get(&1, :status, :published) == :published and URL.has_url?(&1) and site_language?(&1)))
          |> Enum.flat_map(&alternate_hreflang/1)

        conn
        |> put_private(:brando_hreflang_url, canonical_url)
        |> put_entry_alternates(entry.language, hreflangs)
        |> put_entry_page(entry)
    end
  end

  def put_hreflang(conn, _), do: conn

  # Given as paths or URLs, the alternates name no entry to give the page its
  # URL; the page's own language is the request's
  defp put_alternates(conn, alternates) do
    %{conn | private: Map.delete(conn.private, :brando_hreflang_url)}
    |> put_entry_alternates(conn.assigns.language, alternates)
  end

  # `brando_hreflangs` starts with the page's own language at the page's URL,
  # and an application's layout may read it: `put_page_url/2` keeps that first
  # entry the page's URL
  defp put_entry_alternates(conn, language, alternates) do
    put_private(conn, :brando_hreflangs, [{language, page_url(conn) || Utils.current_url(conn)} | alternates])
  end

  @doc """
  The page's alternates, as `{language, url}`, for its `<link rel="alternate">`
  tags: its own language's is the page's URL (`page_url/1`), whatever
  `put_hreflang/2` was given for that language, and comes first; the other
  languages' follow as given, one per language. A page without a URL (an
  error page) or without a language of its own lists only the other
  languages'.
  """
  @spec hreflangs(conn) :: [{atom() | String.t(), String.t()}]
  def hreflangs(%{private: %{brando_hreflangs: [{own, _} | alternates]}} = conn) do
    own = language_key(own)

    others =
      alternates
      |> Enum.map(fn {language, url} -> {language_key(language), url} end)
      |> Enum.reject(fn {language, _} -> language in [own, nil, ""] end)
      |> Enum.uniq_by(&elem(&1, 0))

    # An alternate without a language would be a link with no `hreflang`
    case {own, page_url(conn)} do
      {_own, nil} -> others
      {own, _url} when own in [nil, ""] -> others
      {own, url} -> [{own, url} | others]
    end
  end

  def hreflangs(_conn), do: []

  # Languages as atoms, however the caller gave them (`conn.assigns.language`
  # is a string, an entry's an atom), so one language is one alternate
  defp language_key(language) when is_binary(language) do
    String.to_existing_atom(language)
  rescue
    ArgumentError -> language
  end

  defp language_key(language), do: language

  # A path gets the current site's base URL; a URL stays as it is
  defp with_host("/" <> _ = path), do: Brando.Utils.hostname(path)
  defp with_host(url), do: url

  # An alternate in a language the site does not use (`Brando.Languages`) is not listed
  defp site_language?(alt), do: Brando.Languages.member?(alt.language)

  defp alternate_hreflang(alt) do
    case URL.resolve(alt) do
      url when url in [nil, ""] ->
        log_no_valid_hreflang(alt)
        []

      url ->
        [{alt.language, Brando.Utils.hostname(url)}]
    end
  end

  defp log_no_valid_hreflang(alt) do
    Logger.error("""
    ==> put_hreflang: No valid url found for alternate entry.

    Schema.......: #{alt.__struct__}
    Id...........: ##{alt.id}
    URL template.:

    #{alt.__struct__.__absolute_url_template__()}

    This usually happens when the alternate entry is missing a preload.
    For instance if you have an entry that requires a preloaded category
    to generate a correct url, you must preload this category with
    your alternate_entries:

        opts = %{
          matches: %{slug: slug, category: category},
          status: :published,
          preload: [:category, alternate_entries: [:category]]
        }

    """)
  end

  @doc """
  Sets the URL of the page's `<link rel="canonical">` and `og:url`.

  Without it, the canonical URL is the page's own URL, `page_url/1`. The
  page's JSON-LD keeps that URL: it describes this page, wherever the
  canonical points. `put_meta/3` and `put_hreflang/2` call this for an entry
  with a `meta_canonical_url` (`Brando.Trait.Meta`), so controllers only need
  it for pages that are not entries:

      put_canonical(conn, "https://example.com/original-article")

  """
  @spec put_canonical(conn, String.t() | nil) :: conn
  def put_canonical(conn, url) when is_binary(url) and url != "", do: put_private(conn, :brando_canonical_url, url)
  def put_canonical(conn, _url), do: conn

  @doc "The canonical URL set by `put_canonical/2`, if any."
  @spec get_canonical(conn) :: String.t() | nil
  def get_canonical(conn), do: conn.private[:brando_canonical_url]

  @doc """
  Sets the page's URL (`page_url/1`), for a controller that knows it better
  than the entries it describes the page with. Takes a URL or a path, which
  gets the site's base URL:

      put_page_url(conn, "/projects")

  """
  @spec put_page_url(conn, String.t() | nil) :: conn
  def put_page_url(conn, "/" <> _ = path), do: put_page_url(conn, Utils.hostname(path))

  def put_page_url(conn, url) when is_binary(url) and url != "" do
    conn = put_private(conn, :brando_page_url, url)

    case conn.private[:brando_hreflangs] do
      [{language, _} | alternates] -> put_private(conn, :brando_hreflangs, [{language, url} | alternates])
      _ -> conn
    end
  end

  def put_page_url(conn, _url), do: conn

  @doc """
  The page's URL, which its canonical link, `og:url`, its own language's
  alternate and its JSON-LD `@id`s and `url`s all name. It is chosen when the
  head is rendered, so the order the controller calls these in does not
  matter. The first of these that gives one:

    1. the URL given to `put_page_url/2`;
    2. the URL of the entry given to `put_hreflang/2`;
    3. the request URL, without a trailing slash or its query string.

  The entries given to `put_meta/3` and `put_json_ld/3` do not decide it: a
  section page that describes several routes (`/projects/:slug`,
  `/news/page/2`) leaves each route its own URL. An error response (a status
  outside 200–299, such as the 404 and 410 pages) has no URL: `nil`.

  Like the entry's URL and the sitemap's, it has no trailing slash: a page
  requested at `/about/` has the URL `https://example.com/about`. The front
  page's is the bare origin, `https://example.com`, whose path is `/`.
  """
  @spec page_url(conn) :: String.t() | nil
  def page_url(conn) do
    if error_status?(conn.status),
      do: nil,
      else: conn.private[:brando_page_url] || conn.private[:brando_hreflang_url] || Utils.current_url(conn)
  end

  defp error_status?(nil), do: false
  defp error_status?(status), do: status not in 200..299

  defp maybe_put_entry_canonical(conn, %{meta_canonical_url: url}), do: put_canonical(conn, url)
  defp maybe_put_entry_canonical(conn, _entry), do: conn

  # What an entry with `Brando.Trait.Meta` says about its own page: the
  # canonical override and the snippet limits for the robots meta tag.
  defp put_entry_page(conn, entry) do
    conn
    |> maybe_put_entry_canonical(entry)
    |> put_robots(Brando.Trait.Meta.robots_directives(entry))
    |> put_page_entry(entry)
  end

  # The entry the page is about, for its Markdown version (`Brando.Plug.Markdown`).
  defp put_page_entry(conn, %{__struct__: _} = entry), do: put_private(conn, :brando_page_entry, entry)
  defp put_page_entry(conn, _data), do: conn

  @doc """
  The entry this page is about, as passed to `put_meta/3`, `put_hreflang/2`
  or `put_json_ld/3`.
  """
  @spec get_page_entry(conn) :: struct() | nil
  def get_page_entry(conn), do: conn.private[:brando_page_entry]

  @doc """
  Adds directives to the page's robots meta tag, after any the page already
  has, such as `put_robots(conn, ["noarchive"])`. `put_meta/3` and
  `put_hreflang/2` add an entry's snippet limits (`nosnippet`,
  `max-snippet:N`) from `Brando.Trait.Meta`.
  """
  @spec put_robots(conn, [String.t()]) :: conn
  def put_robots(conn, []), do: conn

  def put_robots(conn, directives) when is_list(directives) do
    existing = conn.private[:brando_robots] || []
    put_private(conn, :brando_robots, Enum.uniq(existing ++ directives))
  end

  @doc "The robots meta directives added with `put_robots/2`."
  @spec get_robots(conn) :: [String.t()]
  def get_robots(conn), do: conn.private[:brando_robots] || []

  @doc """
  Put META data in conn
  """
  def put_meta(conn, module, data, opts \\ [])

  @spec put_meta(conn, module :: atom, data :: any) :: conn
  def put_meta(conn, module, data, _opts) when is_atom(module) do
    meta_meta = %{__meta__: %{current_url: page_url(conn)}}
    data_with_meta = Map.merge(data, meta_meta)
    extracted_meta = Brando.Blueprint.Meta.extract_meta(module, data_with_meta)
    merged_meta = (conn.private[:brando_meta] || []) ++ extracted_meta

    conn
    |> put_private(:brando_meta, merged_meta)
    |> put_entry_page(data)
  end

  def put_meta(conn, key, data, opts) when is_binary(key) do
    meta = conn.private[:brando_meta] || []

    meta =
      if Keyword.get(opts, :replace) do
        Enum.reject(meta, fn {k, _} -> k == key end)
      else
        meta
      end

    put_private(conn, :brando_meta, meta ++ [{key, data}])
  end

  @doc """
  Add meta key if not found in conn
  """
  def put_meta_if_missing(conn, key, data) when is_binary(key) do
    meta = conn.private[:brando_meta] || []

    if Enum.any?(meta, fn {k, _} -> k == key end) do
      conn
    else
      put_private(conn, :brando_meta, meta ++ [{key, data}])
    end
  end
end

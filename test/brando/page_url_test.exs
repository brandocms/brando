defmodule Brando.PageURLTest do
  # A page has one URL in its head: the canonical link, og:url, its own
  # language's alternate and every JSON-LD `@id` and `url` that names the page,
  # whatever path the request used
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Page
  alias Brando.Plug.HTML

  doctest Brando.JSONLD, only: [node_id: 2]

  setup do
    user = Factory.insert(:random_user)

    about = page!(user, "About", "about", :en)
    om = page!(user, "Om", "about", :no)
    Page.Alternate.add(about.id, om.id)

    {:ok, about} = Pages.get_page(%{matches: %{id: about.id}, preload: [:alternate_entries]})
    %{user: user, about: about}
  end

  describe "a page with an entry" do
    test "has the entry's URL, requested with or without a trailing slash", %{about: about} do
      for path <- ["/en/about", "/en/about/"] do
        head = path |> request() |> page_controller(about) |> render_head()
        assert_one_url(head, "http://localhost/en/about", "#webpage")
      end
    end

    test "has the entry's URL when the request used another path to it", %{about: about} do
      head = "/about/" |> request() |> page_controller(about) |> render_head()
      assert_one_url(head, "http://localhost/en/about", "#webpage")
    end

    test "leaves the query string out", %{about: about} do
      head = "/en/about/?utm_source=x&page=2" |> request() |> page_controller(about) |> render_head()
      assert_one_url(head, "http://localhost/en/about", "#webpage")
    end

    test "has the entry's URL with put_meta/3 only, as a generated controller without alternates", %{about: about} do
      head =
        "/en/about/"
        |> request()
        |> HTML.put_meta(Page, about)
        |> HTML.put_json_ld(Page, about)
        |> render_head()

      assert head.canonical == "http://localhost/en/about"
      assert head.og_url == "http://localhost/en/about"
      assert head.webpage["@id"] == "http://localhost/en/about#webpage"
      assert head.webpage["url"] == "http://localhost/en/about"
    end

    test "the entry's own node has the page's URL", %{about: about} do
      head = "/en/about/" |> request() |> page_controller(about) |> render_head()
      article = Enum.find(head.graph, &(&1["@type"] == "Article"))

      assert article["@id"] == "http://localhost/en/about#article"
      assert article["url"] == "http://localhost/en/about"
      assert article["mainEntityOfPage"] == "http://localhost/en/about"
    end
  end

  describe "the home page" do
    test "has one URL in each language, with and without a trailing slash", %{user: user} do
      en = page!(user, "Home", "index", :en)
      no = page!(user, "Hjem", "index", :no)

      for {page, paths} <- [{en, ["/en", "/en/", "/"]}, {no, ["/no", "/no/"]}] do
        url = Brando.Blueprint.URL.resolve(page, :with_host)

        for path <- paths do
          head = path |> request(to_string(page.language)) |> page_controller(page) |> render_head()
          assert_one_url(head, url, "#webpage")
        end
      end
    end
  end

  describe "a page without an entry" do
    test "has the request URL without a trailing slash or query string" do
      for path <- ["/en/news", "/en/news/", "/en/news/?page=2"] do
        head =
          path
          |> request()
          |> HTML.put_hreflang(en: "/en/news", no: "/no/nyheter")
          |> render_head()

        assert head.canonical == "http://localhost/en/news"
        assert head.og_url == "http://localhost/en/news"
        assert {"en", "http://localhost/en/news"} in head.alternates
        assert head.webpage["@id"] == "http://localhost/en/news#webpage"
        assert head.webpage["url"] == "http://localhost/en/news"
      end
    end

    test "has the visited URL when the locale plug adds the language to path_info" do
      head =
        "/news/"
        |> request()
        |> Map.put(:path_info, ["en", "news"])
        |> HTML.put_hreflang(en: "/en/news", no: "/no/nyheter")
        |> render_head()

      assert head.canonical == "http://localhost/news"
      assert head.og_url == "http://localhost/news"
      assert {"en", "http://localhost/news"} in head.alternates
      assert head.webpage["url"] == "http://localhost/news"
    end
  end

  describe "a 404 page" do
    test "has no URL: no canonical, og:url or WebPage node", %{user: user} do
      not_found = page!(user, "Not found", "404", :en, has_url: false)
      {:ok, not_found} = Pages.get_page(%{matches: %{id: not_found.id}, preload: [:alternate_entries]})

      head =
        "/en/missing/"
        |> request()
        |> Plug.Conn.put_status(:not_found)
        |> page_controller(not_found)
        |> render_head()

      assert head.canonical == nil
      assert head.og_url == nil
      assert head.alternates == []
      assert head.webpage == nil
      assert Enum.any?(head.graph, &(&1["@id"] == "http://localhost/#website"))
    end

    test "rendered without a CMS page has no URL either" do
      head = "/en/missing" |> request() |> Plug.Conn.put_status(:not_found) |> render_head()

      assert head.canonical == nil
      assert head.og_url == nil
      assert head.webpage == nil
    end
  end

  # What the generated page controller puts for a CMS page
  defp page_controller(conn, page) do
    conn
    |> HTML.put_meta(Page, page)
    |> HTML.put_json_ld_type(page.json_ld_type)
    |> HTML.put_hreflang(page)
    |> HTML.put_json_ld(Page, page)
  end

  defp request(path, language \\ "en") do
    :get
    |> Plug.Test.conn(path)
    |> Plug.Conn.assign(:language, language)
  end

  defp render_head(conn) do
    assigns = %{conn: conn}

    html =
      rendered_to_string(~H"""
      <Brando.HTML.render_meta conn={@conn} />
      <Brando.HTML.render_json_ld conn={@conn} />
      <Brando.HTML.render_hreflangs conn={@conn} />
      """)

    {:ok, document} = Floki.parse_fragment(html)

    graph =
      case document |> Floki.find(~s(script[type="application/ld+json"])) |> Enum.map(&Floki.children/1) do
        [json] -> json |> Enum.join() |> Jason.decode!() |> Map.fetch!("@graph")
        [] -> []
      end

    %{
      canonical: document |> Floki.attribute(~s(link[rel="canonical"]), "href") |> List.first(),
      og_url: document |> Floki.attribute(~s(meta[property="og:url"]), "content") |> List.first(),
      alternates:
        for(
          link <- Floki.find(document, ~s(link[rel="alternate"][hreflang])),
          do: {link |> Floki.attribute("hreflang") |> hd(), link |> Floki.attribute("href") |> hd()}
        ),
      graph: graph,
      language: conn.assigns.language,
      webpage: Enum.find(graph, &(&1["@type"] in ["WebPage", "AboutPage", "CollectionPage"]))
    }
  end

  # The page's URL in every place that names the page; a node's `@id` is that
  # URL and a fragment (`#webpage` after a bare origin's `/`)
  defp assert_one_url(head, url, fragment) do
    id = if URI.parse(url).path in [nil, ""], do: url <> "/" <> fragment, else: url <> fragment
    language = if head.webpage, do: head.webpage["inLanguage"], else: head.language

    assert head.canonical == url
    assert head.og_url == url
    assert {language, url} in head.alternates or head.alternates == []
    # The test database has an identity in English only, and no graph without one
    if language == "en" or head.graph != [] do
      assert head.webpage["@id"] == id
      assert head.webpage["url"] == url
    end

    for node <- head.graph, node["@type"] not in ["WebSite", "Organization", "BreadcrumbList"], node != head.webpage do
      for key <- ["url", "mainEntityOfPage"], Map.has_key?(node, key), do: assert(node[key] == url)
      if is_binary(node["@id"]), do: assert(String.starts_with?(node["@id"], url <> "#") or node["@id"] == id)
    end
  end

  defp page!(user, title, uri, language, attrs \\ []) do
    params =
      Factory.params_for(:page, Keyword.merge([title: title, uri: uri, language: language, status: :published], attrs))

    {:ok, page} = Pages.create_page(params, user)
    {:ok, page} = Pages.get_page(%{matches: %{id: page.id}, preload: [:alternate_entries]})
    page
  end
end

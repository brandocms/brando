defmodule Brando.PageURLTest do
  # A page has one URL in its head: the canonical link, og:url, its own
  # language's alternate and every JSON-LD `@id` and `url` that names the page,
  # whatever path the request used
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Brando.Factory
  alias Brando.JSONLDTest.Post
  alias Brando.JSONLDTest.QuietPost
  alias Brando.Pages
  alias Brando.Pages.Page
  alias Brando.PageURLTest.Unloaded
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

    test "the entry's own node has the page's URL", %{about: about} do
      head = "/en/about/" |> request() |> page_controller(about) |> render_head()
      article = Enum.find(head.graph, &(&1["@type"] == "Article"))

      assert article["@id"] == "http://localhost/en/about#article"
      assert article["url"] == "http://localhost/en/about"
      assert article["mainEntityOfPage"] == "http://localhost/en/about"
    end
  end

  describe "the home page" do
    setup do
      # An identity in Norwegian as well, for the Norwegian front page's graph
      previous = Brando.Cache.get(:identity)
      Brando.Sites.create_default_identity("no")
      Brando.Cache.put(:identity, Brando.Cache.Identity.load()[:identity], :infinite)
      on_exit(fn -> Brando.Cache.put(:identity, previous, :infinite) end)
    end

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

      head = "/no/" |> request("no") |> page_controller(no) |> render_head()
      assert head.webpage["@id"] == "http://localhost/no#webpage"
    end
  end

  # The page's URL is chosen when the head is rendered, in this order:
  # put_page_url/2, put_hreflang/2's entry, the request URL. The entries given
  # to put_meta/3 and put_json_ld/3 do not decide it: a section page often
  # describes several routes.
  describe "the page's URL" do
    setup %{user: user} do
      projects = page!(user, "Projects", "projects", :en)
      post = %Post{id: 1, title: "A", slug: "a"}
      %{projects: projects, post: post}
    end

    test "is the URL given to put_page_url/2, before put_hreflang/2's entry", %{
      about: about,
      post: post,
      projects: projects
    } do
      calls = [
        &HTML.put_meta(&1, Page, projects),
        &HTML.put_json_ld(&1, Post, post),
        &HTML.put_hreflang(&1, about),
        &HTML.put_page_url(&1, "/acme")
      ]

      for order <- permutations(calls) do
        head = "/elsewhere/" |> request() |> apply_calls(order) |> render_head()
        assert_one_url(head, "http://localhost/acme", "#webpage")
      end
    end

    test "is put_hreflang/2's entry's, whatever put_meta/3 and put_json_ld/3 are given", %{
      about: about,
      post: post,
      projects: projects
    } do
      calls = [&HTML.put_meta(&1, Page, projects), &HTML.put_json_ld(&1, Post, post), &HTML.put_hreflang(&1, about)]

      for order <- permutations(calls) do
        head = "/elsewhere/" |> request() |> apply_calls(order) |> render_head()
        assert_one_url(head, "http://localhost/en/about", "#webpage")
      end
    end

    test "is the request URL when put_meta/3 and put_json_ld/3 are given a section page", %{projects: projects} do
      calls = [
        &HTML.put_meta(&1, Page, projects),
        &HTML.put_json_ld(&1, Page, projects),
        &HTML.put_hreflang(&1, en: "/en/projects/acme", no: "/no/prosjekter/acme")
      ]

      for path <- ["/en/projects/acme", "/en/projects/acme/?page=2"], order <- permutations(calls) do
        head = path |> request() |> apply_calls(order) |> render_head()
        assert_one_url(head, "http://localhost/en/projects/acme", "#webpage")

        assert head.alternates == [
                 {"en", "http://localhost/en/projects/acme"},
                 {"no", "http://localhost/no/prosjekter/acme"}
               ]
      end
    end

    test "is the request URL with an entry with a URL given to put_json_ld/3 only", %{post: post} do
      head = "/news/page/2/" |> request() |> HTML.put_json_ld(Post, post) |> render_head()
      assert_one_url(head, "http://localhost/news/page/2", "#webpage")
    end

    test "is the request URL without an entry with a URL" do
      head = "/elsewhere/?x=1" |> request() |> HTML.put_json_ld(QuietPost, %QuietPost{title: "Q"}) |> render_head()
      assert_one_url(head, "http://localhost/elsewhere", "#webpage")
    end

    test "put_meta/3 and put_json_ld/3 do not resolve their entry's URL" do
      entry = %Unloaded{id: 1, title: "U"}

      log =
        with_log_level(:warning, fn ->
          ExUnit.CaptureLog.capture_log(fn ->
            head =
              "/unloaded/u/"
              |> request()
              |> HTML.put_meta(Unloaded, entry)
              |> HTML.put_json_ld(Unloaded, entry)
              |> render_head()

            assert_one_url(head, "http://localhost/unloaded/u", "#webpage")
          end)
        end)

      refute log =~ "Unloaded"
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
        assert head.alternates == [{"en", "http://localhost/en/news"}, {"no", "http://localhost/no/nyheter"}]
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
      assert head.alternates == [{"en", "http://localhost/news"}, {"no", "http://localhost/no/nyheter"}]
      assert head.webpage["url"] == "http://localhost/news"
    end

    test "an entry whose language is a string has one alternate in it", %{user: user} do
      page = %{page!(user, "Solo", "solo", :en) | language: "en", alternate_entries: []}
      conn = "/en/solo" |> request() |> HTML.put_hreflang(page)

      assert HTML.hreflangs(conn) == [{:en, "http://localhost/en/solo"}]
      assert render_head(conn).alternates == []
    end

    test "a page without a language of its own lists the other languages only" do
      conn =
        "/news"
        |> request()
        |> Plug.Conn.assign(:language, nil)
        |> HTML.put_hreflang(en: "/en/news", no: "/no/nyheter")

      assert HTML.hreflangs(conn) == [{:en, "http://localhost/en/news"}, {:no, "http://localhost/no/nyheter"}]
      refute Enum.any?(render_head(conn).alternates, fn {language, _} -> language in [nil, ""] end)
    end

    test "has one alternate in its own language, whatever the alternates' keys" do
      for alternates <- [[en: "/en/news", no: "/no/nyheter"], [{"en", "/en/news"}, {"no", "/no/nyheter"}]] do
        head = "/news/" |> request() |> HTML.put_hreflang(alternates) |> render_head()
        assert head.alternates == [{"en", "http://localhost/news"}, {"no", "http://localhost/no/nyheter"}]
      end
    end
  end

  # Read the way an application's own layout or controller reads them
  describe "what an application reads from the conn" do
    test "brando_hreflangs has main's shape and order, its first entry the page's URL", %{about: about} do
      conn = "/news/" |> request() |> HTML.put_hreflang(en: "/en/news", no: "/no/nyheter")

      assert conn.private.brando_hreflangs == [
               {"en", "http://localhost/news"},
               {:en, "http://localhost/en/news"},
               {:no, "http://localhost/no/nyheter"}
             ]

      conn = "/about/" |> request() |> HTML.put_hreflang(about)
      assert conn.private.brando_hreflangs == [{:en, "http://localhost/en/about"}, {:no, "http://localhost/no/about"}]

      for conn <- [
            "/about/" |> request() |> HTML.put_hreflang(about) |> HTML.put_page_url("/acme"),
            "/about/" |> request() |> HTML.put_page_url("/acme") |> HTML.put_hreflang(about)
          ] do
        assert conn.private.brando_hreflangs == [{:en, "http://localhost/acme"}, {:no, "http://localhost/no/about"}]
      end
    end

    test "json_ld_entities is a list of entities to_graph_json/1 takes", %{about: about} do
      post = %Post{id: 1, title: "A", slug: "a"}

      conn =
        "/about/"
        |> request()
        |> HTML.put_hreflang(about)
        |> HTML.put_json_ld(Post, post)
        |> HTML.put_json_ld(:entities, [%Brando.JSONLD.Schema.Thing{name: "Acme"}])

      assert [%Brando.JSONLD.Schema.Article{}, %Brando.JSONLD.Schema.Thing{}] = conn.assigns.json_ld_entities

      assert %{"@graph" => [article, %{"name" => "Acme"}]} =
               conn.assigns.json_ld_entities |> Brando.JSONLD.to_graph_json() |> Jason.decode!()

      assert article["@id"] == "http://localhost/en/about#article"
      assert article["url"] == "http://localhost/en/about"
    end

    test "json_ld_main_entity is the person's @id on their profile page" do
      person = %Brando.JSONLDTest.Person{id: 1, name: "Ada", slug: "ada"}
      conn = "/people/ada/" |> request() |> HTML.put_json_ld(Brando.JSONLDTest.Person, person)

      assert conn.assigns.json_ld_page_type == "ProfilePage"
      assert conn.assigns.json_ld_main_entity == "http://localhost/people/ada#person"
    end
  end

  describe "a page about a person" do
    test "is their ProfilePage, about their #person node at the page's URL, whenever that is set" do
      person = %Brando.JSONLDTest.Person{id: 1, name: "Ada", slug: "ada"}

      calls = [&HTML.put_json_ld(&1, Brando.JSONLDTest.Person, person), &HTML.put_page_url(&1, "/team/ada")]

      for order <- permutations(calls) do
        head = "/people/ada/" |> request() |> apply_calls(order) |> render_head()
        profile = Enum.find(head.graph, &(&1["@type"] == "ProfilePage"))

        assert profile["@id"] == "http://localhost/team/ada#webpage"
        assert profile["mainEntity"] == %{"@id" => "http://localhost/team/ada#person"}
        assert Enum.find(head.graph, &(&1["@type"] == "Person"))["@id"] == "http://localhost/team/ada#person"
      end
    end

    test "whose schema makes the entity another type is a WebPage, not a ProfilePage" do
      company = %Brando.PageURLTest.Company{id: 1, name: "Acme", slug: "acme"}
      org_type = [%{name: :"@type", type: :string, value_fn: fn _ -> "Organization" end}]
      person = %Brando.JSONLDTest.Person{id: 1, name: "Ada", slug: "ada"}

      for conn <- [
            "/companies/acme" |> request() |> HTML.put_json_ld(Brando.PageURLTest.Company, company),
            "/people/ada" |> request() |> HTML.put_json_ld(Brando.JSONLDTest.Person, person, org_type)
          ] do
        head = render_head(conn)
        organization = Enum.find(head.graph, &(&1["@id"] == conn |> HTML.page_url() |> Kernel.<>("#organization")))

        assert organization["@type"] == "Organization"
        assert conn.assigns.json_ld_page_type == "WebPage"
        assert head.webpage["@type"] == "WebPage"
        refute Map.has_key?(head.webpage, "mainEntity")
        refute Enum.any?(head.graph, &(&1["@type"] == "ProfilePage"))
      end
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

  defp with_log_level(level, fun) do
    previous = Logger.level()
    Logger.configure(level: level)

    try do
      fun.()
    after
      Logger.configure(level: previous)
    end
  end

  defp apply_calls(conn, calls), do: Enum.reduce(calls, conn, & &1.(&2))

  defp permutations([]), do: [[]]
  defp permutations(list), do: for(x <- list, rest <- permutations(list -- [x]), do: [x | rest])

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
    language = if head.webpage, do: head.webpage["inLanguage"], else: head.language

    assert head.canonical == url
    assert head.og_url == url
    assert {language, url} in head.alternates or head.alternates == []
    assert head.webpage["@id"] == node_id(url, fragment)
    assert head.webpage["url"] == url

    for node <- head.graph, node["@type"] not in ["WebSite", "Organization", "BreadcrumbList"], node != head.webpage do
      assert_node_url(node, url)
    end
  end

  defp assert_node_url(node, url) do
    for key <- ["url", "mainEntityOfPage"], Map.has_key?(node, key), do: assert(node[key] == url)
    if is_binary(node["@id"]), do: assert(node["@id"] == node_id(url, "#" <> String.downcase(node["@type"])))
  end

  defp node_id(url, fragment) do
    if URI.parse(url).path in [nil, ""], do: url <> "/" <> fragment, else: url <> fragment
  end

  defp page!(user, title, uri, language, attrs \\ []) do
    params =
      Factory.params_for(:page, Keyword.merge([title: title, uri: uri, language: language, status: :published], attrs))

    {:ok, page} = Pages.create_page(params, user)
    {:ok, page} = Pages.get_page(%{matches: %{id: page.id}, preload: [:alternate_entries]})
    page
  end
end

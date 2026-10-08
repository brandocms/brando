defmodule Brando.JSONLD.InspectorTest do
  # Renders the whole @graph, which reads the cached identity.
  use Brando.ConnCase, async: false

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Brando.HTML, only: [render_json_ld: 1]

  alias Brando.Content.Block
  alias Brando.Content.Var
  alias Brando.JSONLD.Inspector
  alias Brando.JSONLDTest.Post
  alias Brando.JSONLDTest.QuietPost
  alias Brando.Users.User
  alias Brando.Videos.Video

  defp video(id, attrs \\ []) do
    struct(
      %Video{
        id: id,
        type: :mux,
        status: :ready,
        title: "Video #{id}",
        inserted_at: ~N[2026-03-04 10:20:30],
        meta: %{"mux" => %{"playback_id" => "playback-#{id}"}}
      },
      attrs
    )
  end

  defp creator do
    %User{id: 12, name: "Grace Editor", job_title: "Editor", same_as: [], avatar: %Ecto.Association.NotLoaded{}}
  end

  defp post(attrs \\ []) do
    struct(
      %Post{
        title: "On engines",
        slug: "on-engines",
        creator: creator(),
        writer: nil,
        cover_video: video(1),
        entry_blocks: []
      },
      attrs
    )
  end

  # The page as a controller following the guide renders it.
  defp emitted(module, entry, path, title) do
    conn =
      :get
      |> Plug.Test.conn(path)
      |> Brando.Plug.I18n.put_locale(skip_session: true)
      |> Brando.Plug.HTML.put_title(title)
      |> Brando.Plug.HTML.put_json_ld(module, entry)

    assigns = %{conn: conn}
    html = rendered_to_string(~H"<.render_json_ld conn={@conn} />")
    [json] = Regex.run(~r/<script[^>]*>([\s\S]*?)<\/script>/, html, capture: :all_but_first)
    String.trim(json)
  end

  defp node(inspection, type), do: Enum.find(inspection.nodes, &(&1.type == type))
  defp row(node, property), do: Enum.find(node.rows, &(&1.property == property))

  test "the inspector's JSON-LD is exactly what the page emits" do
    entry = post()
    inspection = Inspector.build(Post, entry)

    assert inspection.json == emitted(Post, entry, "/posts/on-engines", "On engines")
    assert inspection.url == "http://localhost/posts/on-engines"
  end

  test "one node per entity, with edges named by the linking property" do
    inspection = Inspector.build(Post, post())

    assert inspection.nodes |> Enum.map(& &1.type) |> Enum.sort() ==
             ~w(Article ImageObject Organization Person VideoObject WebPage WebSite)

    labels =
      for %{from: from, to: to, label: label} <- inspection.edges do
        types = Enum.map([from, to], fn key -> Enum.find(inspection.nodes, &(&1.key == key)).type end)
        {types, label}
      end

    assert {["WebSite", "Organization"], "publisher"} in labels
    assert {["WebPage", "WebSite"], "isPartOf"} in labels
    assert {["Article", "Organization"], "publisher"} in labels
    assert {["Article", "Person"], "author"} in labels
    assert {["Article", "VideoObject"], "video"} in labels
    assert {["Article", "ImageObject"], "image"} in labels

    article = node(inspection, "Article")
    assert inspection.main == article.key
    assert article.ref == "http://localhost/posts/on-engines/#article"
    assert Inspector.short_id(article.ref) == "/posts/on-engines/#article"
    assert Inspector.short_id(node(inspection, "Organization").ref) == "#identity"
  end

  test "lays the graph out in layers, deterministically and without overlaps" do
    inspection = Inspector.build(Post, post())
    layer = &node(inspection, &1).layer

    assert layer.("WebSite") == 0
    assert layer.("Organization") == 1 and layer.("WebPage") == 1
    assert layer.("Article") == 2
    assert layer.("Person") == 3 and layer.("VideoObject") == 3 and layer.("ImageObject") == 3

    positions = Enum.map(inspection.nodes, &{&1.x, &1.y})
    assert positions == Enum.uniq(positions)
    assert Enum.all?(inspection.nodes, &(&1.x >= 0 and &1.x + 184 <= inspection.width))
    assert Inspector.build(Post, post()) == inspection
  end

  test "maps each property to the field or setting it comes from" do
    article = node(Inspector.build(Post, post()), "Article")

    assert row(article, "author").source == {:fields, [["creator", "writer"]]}
    assert row(article, "headline").source == {:fields, [["title"]]}
    assert row(article, "publisher").source == :identity
    assert row(article, "url").source == :page_url
    assert row(article, "video").source == :videos
    assert row(article, "headline").status == :ok

    # Google recommends what the blueprint doesn't map.
    assert %{source: :not_mapped, mapped: false, status: :warning} = row(article, "image")
    assert %{source: :not_mapped, status: :warning} = row(article, "datePublished")

    # The author has no profile links or page, which Google recommends.
    assert %{status: :warning, issues: [%{property: "author.url | author.sameAs"}]} = row(article, "author")

    person = node(Inspector.build(Post, post()), "Person")
    assert row(person, "name").source == {:fields, [["name"]]}
    assert row(person, "jobTitle").source == {:fields, [["job_title"]]}
  end

  test "dashed nodes show what the page would gain" do
    image = node(Inspector.build(Post, post()), "ImageObject")
    assert %{role: :potential, property: "image", potential: :not_mapped} = image

    no_video = Inspector.build(Post, post(cover_video: nil))
    assert %{role: :potential, potential: :not_set} = node(no_video, "VideoObject")

    no_author = Inspector.build(Post, post(creator: nil))
    assert %{role: :potential, property: "author", potential: :not_set} = node(no_author, "Person")

    # A blueprint that maps no author and opts out of videos
    quiet = Inspector.build(QuietPost, %QuietPost{title: "Quiet", creator: creator(), cover_video: video(1)})
    assert %{role: :potential, potential: :not_mapped} = node(quiet, "Person")
    refute node(quiet, "VideoObject")
  end

  test "sources follow fallbacks and call computed values computed" do
    sources = Inspector.sources(Brando.Pages.Page)

    assert sources[:headline] == {:fields, [["title"]]}
    assert sources[:dateModified] == {:fields, [["content_modified_at"], ["edited_at"]]}
    assert sources[:copyrightYear] == :computed
    assert sources[:author] == :identity
    assert sources[:inLanguage] == :language
    assert sources[:mainEntityOfPage] == :page_url
    assert sources[:image] == {:fields, [["meta_image"]]}
  end

  test "preloads what the mapping reads" do
    preloads = Inspector.preloads(Post, blocks: false)

    assert {:creator, [:avatar]} in preloads
    assert :writer in preloads
    assert {:cover_video, [:thumbnail, :file]} in preloads
  end

  test "entry issues leave out the site's identity" do
    inspection = Inspector.build(Post, post())
    issues = Inspector.entry_issues(inspection)

    refute Enum.any?(issues, &(&1.type in ["Organization", "WebSite"]))
    assert Enum.any?(issues, &(&1.type == "Article"))
  end

  test "videos in block variables are described, like refs" do
    var = %Var{type: :video, key: "background", video: video(7)}
    entry = post(cover_video: nil, entry_blocks: [%{block: %Block{active: true, refs: [], vars: [var], children: []}}])

    assert [%{"@id": "http://localhost/#/schema/video/7"}] = Brando.JSONLD.Videos.from_entry(Post, entry)

    hidden = post(cover_video: nil, entry_blocks: [%{block: %Block{active: false, refs: [], vars: [var], children: []}}])
    assert Brando.JSONLD.Videos.from_entry(Post, hidden) == []
  end

  describe "a mapping that reads a relation" do
    # A site's field function may enumerate a relation (`keywords/1` listing
    # an entry's categories). The Structured data tab loads the entry with
    # the blueprint's relations, as its form does; before, it loaded only
    # what probing the mapping found, and the field function raised on the
    # relation that wasn't loaded.
    alias Brando.JSONLDTest.Shelf

    setup do
      page = Brando.Factory.insert(:page)

      for key <- ["oak", "pine"] do
        Brando.Repo.insert!(%Var{type: :string, key: key, label: %{"en" => key}, page_id: page.id})
      end

      shelves = [
        %Shelf{id: page.id, title: "Wood", slug: "wood"},
        %Shelf{id: page.id + 1, title: "Broken", slug: "broken"}
      ]

      Brando.Test.Support.put_test_env(Brando.JSONLDTest, shelves: shelves)
      %{page: page}
    end

    test "loads the blueprint's relations, so a field function can enumerate one", %{page: page} do
      assert :vars in Inspector.preloads(Shelf)

      assert {:ok, inspection, entry} = Inspector.inspect_entry(Shelf, page.id)
      assert Enum.map(entry.vars, & &1.key) |> Enum.sort() == ["oak", "pine"]
      assert inspection.json =~ ~r/"description":"(oak, pine|pine, oak)"/
    end

    test "an entry whose field function raises is an error, not a crash", %{page: page} do
      assert {:error, {:build_failed, "the shelf has no description"}} = Inspector.inspect_entry(Shelf, page.id + 1)
    end
  end
end

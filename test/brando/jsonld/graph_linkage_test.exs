defmodule Brando.JSONLD.GraphLinkageTest do
  # Renders the whole @graph, which reads the cached identity.
  use ExUnit.Case
  use Brando.ConnCase, async: false
  import Phoenix.Component
  import Phoenix.LiveViewTest
  import Brando.HTML

  alias Brando.Content.Block
  alias Brando.Content.Ref
  alias Brando.JSONLDTest.Person, as: PeopleEntry
  alias Brando.JSONLDTest.Post
  alias Brando.JSONLDTest.QuietPost
  alias Brando.Users.User
  alias Brando.Videos.Video
  alias Brando.Villain.Blocks.VideoBlock

  defp writer do
    %PeopleEntry{
      id: 3,
      name: "Ada Lovelace",
      slug: "ada",
      job_title: "Analyst",
      email: "ada.private@example.test",
      portrait: %Ecto.Association.NotLoaded{}
    }
  end

  defp creator do
    %User{
      id: 12,
      name: "Grace Editor",
      email: "grace@example.test",
      password: "hashed-secret",
      role: :admin,
      job_title: "Editor",
      same_as: ["https://www.linkedin.com/in/grace"],
      avatar: %Ecto.Association.NotLoaded{}
    }
  end

  defp video(id, attrs) do
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

  defp video_block(video, opts \\ []) do
    %Block{
      active: Keyword.get(opts, :active, true),
      refs: [
        %Ref{
          active: true,
          video: video,
          data: %VideoBlock{data: %VideoBlock.Data{title: Keyword.get(opts, :title)}}
        }
      ],
      children: Keyword.get(opts, :children, [])
    }
  end

  defp post(attrs \\ []) do
    struct(
      %Post{
        title: "On engines",
        slug: "on-engines",
        creator: creator(),
        writer: writer(),
        cover_video: video(1, []),
        entry_blocks: [
          %{block: video_block(video(2, []), title: "Engine at rest")},
          # Hidden blocks don't render; nested ones do; a repeated video counts once.
          %{block: video_block(video(3, []), active: false)},
          %{block: %Block{active: true, refs: [], children: [video_block(video(4, []))]}},
          %{block: video_block(video(1, []))},
          # Not enough to describe: no node.
          %{block: video_block(video(5, title: nil))}
        ]
      },
      attrs
    )
  end

  defp render_graph(conn) do
    assigns = %{conn: conn}

    html =
      rendered_to_string(~H"""
      <.render_json_ld conn={@conn} />
      """)

    [json] = Regex.run(~r/<script[^>]*>([\s\S]*?)<\/script>/, html, capture: :all_but_first)
    {json, Jason.decode!(json)}
  end

  defp conn(path) do
    :get
    |> Plug.Test.conn(path)
    |> Brando.Plug.I18n.put_locale(skip_session: true)
  end

  defp nodes(graph, type), do: Enum.filter(graph["@graph"], &(&1["@type"] == type))
  defp node(graph, id), do: Enum.find(graph["@graph"], &(&1["@id"] == id))

  test "the article links its authors and videos to their own nodes" do
    {json, graph} = "/posts/on-engines" |> conn() |> Brando.Plug.HTML.put_json_ld(Post, post()) |> render_graph()

    [article] = nodes(graph, "Article")
    assert article["@id"] == "http://localhost/posts/on-engines/#article"

    # author → Person nodes
    assert [%{"@id" => user_id}, %{"@id" => "http://localhost/people/ada/#person"} = writer_ref] = article["author"]
    assert map_size(writer_ref) == 1

    assert %{"@type" => "Person", "name" => "Grace Editor", "jobTitle" => "Editor"} = node(graph, user_id)
    assert node(graph, user_id)["sameAs"] == ["https://www.linkedin.com/in/grace"]

    assert %{"@type" => "Person", "name" => "Ada Lovelace", "url" => "http://localhost/people/ada"} =
             node(graph, "http://localhost/people/ada/#person")

    assert length(nodes(graph, "Person")) == 2

    # video → VideoObject nodes: the cover video, the block videos in page order, once each
    assert article["video"] == [
             %{"@id" => "http://localhost/#/schema/video/1"},
             %{"@id" => "http://localhost/#/schema/video/2"},
             %{"@id" => "http://localhost/#/schema/video/4"}
           ]

    assert %{"name" => "Engine at rest", "thumbnailUrl" => _, "uploadDate" => _} =
             node(graph, "http://localhost/#/schema/video/2")

    assert length(nodes(graph, "VideoObject")) == 3

    # Nothing private about the people
    refute json =~ "grace@example.test"
    refute json =~ "ada.private@example.test"
    refute json =~ "hashed-secret"
    refute json =~ "\"admin\""
  end

  test "videos that are not preloaded are not looked up" do
    post = post(cover_video: %Ecto.Association.NotLoaded{}, entry_blocks: %Ecto.Association.NotLoaded{})
    {_json, graph} = "/posts/on-engines" |> conn() |> Brando.Plug.HTML.put_json_ld(Post, post) |> render_graph()

    assert nodes(graph, "VideoObject") == []
    refute Map.has_key?(hd(nodes(graph, "Article")), "video")
  end

  test "a blueprint that opts out of videos and maps no author gets neither" do
    quiet = %QuietPost{title: "Quiet", creator: creator(), cover_video: video(1, [])}
    {json, graph} = "/quiet" |> conn() |> Brando.Plug.HTML.put_json_ld(QuietPost, quiet) |> render_graph()

    article = hd(nodes(graph, "Article"))
    refute Map.has_key?(article, "video")
    refute Map.has_key?(article, "author")
    assert nodes(graph, "VideoObject") == []
    refute json =~ "Grace Editor"
  end

  test "a person's own page is a ProfilePage about the same Person the article credits" do
    {_json, graph} = "/people/ada" |> conn() |> Brando.Plug.HTML.put_json_ld(PeopleEntry, writer()) |> render_graph()

    [profile] = nodes(graph, "ProfilePage")
    assert profile["mainEntity"] == %{"@id" => "http://localhost/people/ada/#person"}

    assert [%{"@id" => "http://localhost/people/ada/#person", "name" => "Ada Lovelace", "jobTitle" => "Analyst"}] =
             nodes(graph, "Person")

    assert nodes(graph, "WebPage") == []
  end
end

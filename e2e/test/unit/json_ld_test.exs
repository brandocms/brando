defmodule E2eProjectWeb.JSONLDTest do
  use E2eProjectWeb.ConnCase, async: false

  alias E2eProject.Projects.{Client, Project}
  alias E2eProject.Repo

  test "a project page credits its creator and describes its cover video", %{conn: conn} do
    Code.ensure_loaded!(Brando.RuntimeConfig.router_helpers())

    user =
      Repo.insert!(%Brando.Users.User{
        name: "Ada Author",
        email: "ada-author@example.test",
        password: "unused-in-test",
        role: :editor,
        language: :en,
        job_title: "Writer",
        same_as: ["https://www.linkedin.com/in/ada-author"],
        config: %Brando.Users.UserConfig{}
      })

    video =
      Repo.insert!(%Brando.Videos.Video{
        title: "Engine room",
        type: :mux,
        status: :ready,
        duration: "00:02:10",
        meta: %{"provider" => "mux", "mux" => %{"playback_id" => "e2e-playback"}},
        creator_id: user.id
      })

    client = Repo.insert!(%Client{name: "JSON-LD client", slug: "json-ld-client", creator_id: user.id, language: :en})

    Repo.insert!(%Project{
      title: "Structured project",
      slug: "structured-project",
      introduction: "<p>Intro</p>",
      client_id: client.id,
      creator_id: user.id,
      cover_video_id: video.id,
      language: :en,
      status: :published
    })

    html = conn |> get("/project/structured-project") |> html_response(200)

    [json] = Regex.run(~r{<script type="application/ld\+json">([\s\S]*?)</script>}, html, capture: :all_but_first)
    graph = Jason.decode!(json)["@graph"]

    article = Enum.find(graph, &(&1["@type"] == "Article"))
    assert article["headline"] == "Structured project"

    %{"@id" => author_id} = article["author"]
    person = Enum.find(graph, &(&1["@id"] == author_id))
    assert %{"@type" => "Person", "name" => "Ada Author", "jobTitle" => "Writer"} = person
    assert person["sameAs"] == ["https://www.linkedin.com/in/ada-author"]

    %{"@id" => video_id} = article["video"]
    video_node = Enum.find(graph, &(&1["@id"] == video_id))

    assert %{
             "@type" => "VideoObject",
             "name" => "Engine room",
             "thumbnailUrl" => "https://image.mux.com/e2e-playback/thumbnail.jpg",
             "contentUrl" => "https://stream.mux.com/e2e-playback.m3u8",
             "duration" => "PT2M10S",
             "uploadDate" => _
           } = video_node

    refute json =~ "ada-author@example.test"
  end
end

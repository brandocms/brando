defmodule Mix.Tasks.Brando.Upgrade.SnapshotTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Pages
  alias Brando.Upgrade.Snapshot
  alias Brando.Upgrade.Snapshot.Diff
  alias Mix.Tasks.Brando.Upgrade.Snapshot, as: SnapshotTask
  alias Plug.Conn

  @moduletag :tmp_dir

  defp page(body, attrs \\ []) do
    Map.merge(
      %{path: "/no/meny", status: 200, content_type: "text/html; charset=utf-8", location: nil, body: body},
      Map.new(attrs)
    )
  end

  defp html(head, body) do
    """
    <!DOCTYPE html>
    <html lang="no">
      <head>
        <meta charset="utf-8">
        #{head}
      </head>
      <body>#{body}</body>
    </html>
    """
  end

  @head """
  <title>Meny | Lett</title>
  <meta name="csrf-token" content="first-token">
  <meta property="og:locale" content="no">
  <link rel="stylesheet" href="/css/app.css">
  """

  describe "Diff.compare/3" do
    test "an identical page has no layers, whatever its CSRF token and whitespace" do
      before_page = page(html(@head, "<main><h1>Meny</h1><p>Bowls og wraps</p></main>"))

      after_page =
        page(
          html(
            String.replace(@head, "first-token", "second-token"),
            "<main>\n  <h1>Meny</h1>\n  <p>Bowls   og wraps</p>\n</main>"
          )
        )

      assert Diff.compare(before_page, after_page) == []
    end

    test "a data-src that moved from the video to its wrapper shows in the structure only" do
      before_page =
        page(
          html(@head, """
          <div data-smart-video>
            <video muted loop playsinline data-video data-src="https://player.vimeo.com/x.mp4"></video>
          </div>
          """)
        )

      after_page =
        page(
          html(@head, """
          <div class="video-wrapper video-file" data-smart-video data-src="https://player.vimeo.com/x.mp4">
            <video loop playsinline data-video src="https://player.vimeo.com/x.mp4"></video>
          </div>
          """)
        )

      assert [%{layer: :structure, summary: "-2 +2", lines: lines}] = Diff.compare(before_page, after_page)

      assert lines == [
               "- div[data-smart-video]",
               "- video[data-src data-video]",
               "+ div.video-file.video-wrapper[data-smart-video data-src]",
               "+ video[data-video]"
             ]
    end

    test "a reordered list shows in the text, not the structure" do
      before_page = page(html(@head, "<ul class=\"tabs\"><li>Wraps</li><li>Dricka</li><li>Bowls</li></ul>"))
      after_page = page(html(@head, "<ul class=\"tabs\"><li>Dricka</li><li>Wraps</li><li>Bowls</li></ul>"))

      assert [%{layer: :text, lines: lines}] = Diff.compare(before_page, after_page)
      assert "- Wraps" in lines
      assert "+ Wraps" in lines
      refute Enum.any?(lines, &String.contains?(&1, "Bowls"))
    end

    test "a changed head tag shows in the head as a set, and reordering does not" do
      reordered = """
      <link href="/css/app.css" rel="stylesheet">
      <meta content="nb_NO" property="og:locale">
      <title>Meny | Lett</title>
      <script type="application/ld+json">{"@type": "Organization"}</script>
      """

      before_page = page(html(@head, "<p>Meny</p>"))
      after_page = page(html(reordered, "<p>Meny</p>"))

      assert [%{layer: :head, summary: "-2 +2", lines: lines}] = Diff.compare(before_page, after_page)

      assert lines == [
               ~s(- meta name="csrf-token"),
               ~s(- meta property="og:locale" content="no"),
               ~s(+ meta property="og:locale" content="nb_NO"),
               ~s(+ script type="application/ld+json" {"@type":"Organization"})
             ]
    end

    # JSON-LD is now encoded HTML-safe (`https:\/\/`): a snapshot from before
    # holds the same data
    test "JSON-LD compares by its data, not how it is escaped" do
      escaped = ~s(<script type="application/ld+json">{"url": "https:\\/\\/example.com\\/a"}</script>)
      plain = ~s(<script type="application/ld+json">{"url": "https://example.com/a"}</script>)

      assert Diff.compare(page(html(plain, "<p>Meny</p>")), page(html(escaped, "<p>Meny</p>"))) == []
    end

    test "images count as text by their alt, and text in scripts and styles does not" do
      before_page = page(html(@head, ~s(<img src="a.jpg"><script>var x = "hidden"</script><p>Burrata</p>)))
      after_page = page(html(@head, ~s(<img src="a.jpg" alt="Burrata"><style>p { color: red }</style><p>Burrata</p>)))

      assert [%{layer: :text, lines: [~s(- [img alt=""]), ~s(+ [img alt="Burrata"])]}, %{layer: :structure}] =
               Diff.compare(before_page, after_page)
    end

    test "a status or redirect change, and a body that is not HTML compared by line" do
      assert [%{layer: :status, summary: "302 /no → 302 /se"}] =
               Diff.compare(page("", status: 302, location: "/no"), page("", status: 302, location: "/se"))

      robots = &page(&1, path: "/robots.txt", content_type: "text/plain")

      assert [%{layer: :status, summary: "200 → 404"}, %{layer: :text, lines: ["- Disallow: /admin"]}] =
               Diff.compare(
                 robots.("User-agent: *\nDisallow: /admin\n"),
                 robots.("User-agent: *\n") |> Map.put(:status, 404)
               )
    end

    test ":layers leaves the others out" do
      before_page = page(html(@head, "<p>Wraps</p>"), status: 200)
      after_page = page(html(@head, "<div><p>Dricka</p></div>"), status: 404)

      assert [%{layer: :text}] = Diff.compare(before_page, after_page, layers: [:text])
    end
  end

  describe "capture and diff" do
    defp site(pages) do
      fn conn ->
        case Map.fetch(pages, conn.request_path) do
          {:ok, {status, content_type, body}} ->
            conn |> Conn.put_resp_content_type(content_type) |> Conn.send_resp(status, body)

          :error ->
            location = "http://#{conn.host}:#{conn.port}/no"
            conn |> Conn.put_resp_header("location", location) |> Conn.send_resp(302, "")
        end
      end
    end

    test "status/3 asks a site for one path, without following redirects" do
      old_site = site(%{"/no/meny" => {200, "text/html", "<p>Meny</p>"}, "/en/menu" => {404, "text/html", ""}})
      opts = [req_options: [plug: old_site]]

      assert Snapshot.status("/no/meny", "http://lett.test:4000/", opts) == 200
      assert Snapshot.status("/en/menu", "http://lett.test:4000", opts) == 404
      assert Snapshot.status("/elsewhere", "http://lett.test:4000", opts) == 302
    end

    test "captures each URL's status and body, and diffs two captures URL by URL", %{tmp_dir: tmp_dir} do
      urls = Path.join(tmp_dir, "urls.txt")
      File.write!(urls, "/\n\n# a comment\n[info] stray log line\n/no/meny\n/no/kjøpsvilkår\n/robots.txt\n")
      assert Snapshot.read_urls(urls) == ["/", "/no/meny", "/no/kjøpsvilkår", "/robots.txt"]

      # Each side runs on its own port, and its absolute URLs say so.
      og_image = &~s(<meta property="og:image" content="http://lett.test:#{&1}/media/a.jpg">)

      before_site =
        site(%{
          "/no/meny" => {200, "text/html", html(@head, "<ul><li>Wraps</li><li>Dricka</li></ul>")},
          "/no/kj%C3%B8psvilk%C3%A5r" => {200, "text/html", html(og_image.(4000), "<p>Vilkår</p>")},
          "/robots.txt" => {200, "text/plain", "User-agent: *\n"}
        })

      after_site =
        site(%{
          "/no/meny" => {200, "text/html", html(@head, "<ul><li>Dricka</li><li>Wraps</li></ul>")},
          "/no/kj%C3%B8psvilk%C3%A5r" => {200, "text/html", html(og_image.(4001), "<p>Vilkår</p>")},
          "/robots.txt" => {200, "text/plain", "User-agent: *\n"}
        })

      before_dir = Path.join(tmp_dir, "before")
      after_dir = Path.join(tmp_dir, "after")
      paths = Snapshot.read_urls(urls)

      captured = Snapshot.capture(paths, before_dir, base_url: "http://lett.test:4000/", req_options: [plug: before_site])

      assert Enum.map(captured, &{&1.path, &1.status}) == [
               {"/", 302},
               {"/no/meny", 200},
               {"/no/kjøpsvilkår", 200},
               {"/robots.txt", 200}
             ]

      assert File.read!(Path.join(before_dir, "no__meny.html")) =~ "<li>Wraps</li>"
      assert File.exists?(Path.join(before_dir, "ROOT.html"))

      Snapshot.capture(paths, after_dir, base_url: "http://lett.test:4001", req_options: [plug: after_site])
      assert [%{path: "/", status: 302, location: "/no"} | _] = Snapshot.read(after_dir)

      Mix.shell(Mix.Shell.Process)
      on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

      SnapshotTask.run(["diff", before_dir, after_dir])
      assert_received {:mix_shell, :info, [report]}

      assert report =~ "/no/meny\n  text      -1 +1\n    - Wraps\n    + Wraps\n"
      refute report =~ "/no/kjøpsvilkår"
      assert report =~ "4 URLs: 3 identical, 1 differ (text 1)"
    end

    test "a head change every URL shares is reported once" do
      layout = ~s(<link rel="preload" href="/fonts/a.woff2?vsn=d">)
      new_layout = ~s(<link rel="preload" href="/fonts/a.woff2">)

      before = [
        page(html(layout, "<p>Meny</p>"), path: "/no/meny"),
        page(html(layout <> ~s(<meta property="og:locale" content="no">), "<p>Om</p>"), path: "/no/om")
      ]

      after_pages = [
        page(html(new_layout, "<p>Meny</p>"), path: "/no/meny"),
        page(html(new_layout <> ~s(<meta property="og:locale" content="nb_NO">), "<p>Om</p>"), path: "/no/om")
      ]

      report = before |> Snapshot.compare(after_pages) |> Snapshot.report()

      assert report =~ """
             Every URL with a head change (2) has these:
               head      -1 +1
                 - link rel="preload" href="/fonts/a.woff2?vsn=d"
                 + link rel="preload" href="/fonts/a.woff2"
             """

      assert report =~ "/no/meny\n  head      only the shared head changes\n"

      assert report =~ """
             /no/om
               head      -1 +1
                 - meta property="og:locale" content="no"
                 + meta property="og:locale" content="nb_NO"
             """

      assert report =~ "2 URLs: 0 identical, 2 differ (head 2)"
    end

    test "diff says when a directory holds no snapshot", %{tmp_dir: tmp_dir} do
      assert_raise Mix.Error, ~r/holds no snapshot/, fn ->
        SnapshotTask.run(["diff", tmp_dir, tmp_dir])
      end
    end
  end

  describe "the URL set from the database" do
    test "every published page per language, one entry per other Blueprint, 404s, robots and sitemap" do
      user = Brando.Factory.insert(:random_user)

      for {title, uri, language, status} <- [
            {"Menu", "snapshot-menu", "en", :published},
            {"Meny", "snapshot-meny", "no", :published},
            {"Hidden", "snapshot-draft", "en", :draft}
          ] do
        {:ok, _} =
          Pages.create_page(
            %{title: title, uri: uri, language: language, template: "default.html", status: status},
            user
          )
      end

      {paths, _warnings} = Snapshot.URLs.list()

      assert "/" in paths
      assert "/robots.txt" in paths
      assert "/sitemap.xml" in paths
      assert "/no/brando-upgrade-snapshot-missing" in paths
      assert "/en/brando-upgrade-snapshot-missing" in paths
      assert Enum.any?(paths, &String.ends_with?(&1, "/snapshot-menu"))
      assert Enum.any?(paths, &String.ends_with?(&1, "/snapshot-meny"))
      refute Enum.any?(paths, &String.ends_with?(&1, "/snapshot-draft"))
      assert paths == paths |> Enum.uniq() |> Enum.sort()
    end

    test "picks the entries with the most blocks" do
      user = Brando.Factory.insert(:random_user)
      module = Brando.Factory.insert(:module)

      pages =
        for {uri, blocks} <- [{"snapshot-light", 1}, {"snapshot-heavy", 3}, {"snapshot-empty", 0}] do
          page_with_blocks(user, module, uri, blocks)
        end

      [light, heavy, empty] = pages
      assert Snapshot.URLs.heaviest(Pages.Page, %{language: "en"}, 2) |> Enum.map(& &1.id) == [heavy.id, light.id]
      assert Snapshot.URLs.heaviest(Pages.Page, %{language: "en"}, 5) |> List.last() |> Map.get(:id) == empty.id
    end

    test "entries without a URL don't use up the candidates" do
      user = Brando.Factory.insert(:random_user)
      module = Brando.Factory.insert(:module)

      for n <- 1..12 do
        user
        |> page_with_blocks(module, "snapshot-section-#{n}", 2)
        |> Ecto.Changeset.change(has_url: false)
        |> Brando.Repo.update!()
      end

      page_with_blocks(user, module, "snapshot-light-public", 1)

      assert Enum.any?(
               Snapshot.URLs.candidate_paths(Pages.Page, %{language: "en"}),
               &String.ends_with?(&1, "/snapshot-light-public")
             )
    end

    test "leaves out entry URLs the old site answers with 404" do
      user = Brando.Factory.insert(:random_user)

      for {uri, language} <- [{"snapshot-kept", "en"}, {"snapshot-gone", "en"}] do
        {:ok, _} =
          Pages.create_page(
            %{title: uri, uri: uri, language: language, template: "default.html", status: :published},
            user
          )
      end

      {paths, warnings} = Snapshot.URLs.list(found?: &(not String.ends_with?(&1, "/snapshot-gone")))

      assert Enum.any?(paths, &String.ends_with?(&1, "/snapshot-kept"))
      refute Enum.any?(paths, &String.ends_with?(&1, "/snapshot-gone"))
      # The 404 probes, robots and sitemap stay: they are there to compare.
      assert "/brando-upgrade-snapshot-missing" in paths
      assert Enum.any?(warnings, &(&1 =~ "404 on the old site: /en/snapshot-gone"))
    end
  end

  defp page_with_blocks(user, module, uri, count) do
    blocks =
      for n <- 1..count//1 do
        %Brando.Pages.Page.Blocks{
          sequence: n,
          block: %Brando.Content.Block{
            type: :module,
            source: "Elixir.Brando.Pages.Page.Blocks",
            module_id: module.id,
            uid: Brando.Utils.generate_uid(),
            sequence: n,
            refs: [],
            vars: []
          }
        }
        |> Ecto.Changeset.change()
        |> Map.put(:action, :insert)
      end

    params = %{title: uri, uri: uri, language: "en", template: "default.html", status: :published}

    changeset =
      %Pages.Page{}
      |> Pages.Page.changeset(params, user)
      |> Ecto.Changeset.put_assoc(:entry_blocks, blocks)
      |> Map.put(:action, :insert)

    {:ok, page} = Pages.create_page(changeset, user)
    page
  end
end

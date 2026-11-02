defmodule Brando.Sites.FourOhFourLogTest do
  # The buffer is one global cache.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Ecto.Query, only: [from: 2]
  import ExUnit.CaptureLog, only: [capture_log: 1]

  alias Brando.Sites.FourOhFour
  alias Brando.Sites.NotFoundHit

  setup do
    Cachex.clear(:four_oh_four)
    on_exit(fn -> Cachex.clear(:four_oh_four) end)
    :ok
  end

  defp miss(path, referrer \\ nil) do
    conn = %Plug.Conn{path_info: String.split(path, "/", trim: true)}
    conn = if referrer, do: Plug.Conn.put_req_header(conn, "referer", referrer), else: conn
    FourOhFour.add_404(conn)
  end

  defp warnings_of(fun) do
    level = Logger.level()
    Logger.configure(level: :warning)
    on_exit(fn -> Logger.configure(level: level) end)
    capture_log(fun)
  end

  defp rows, do: Brando.Repo.all(from h in NotFoundHit, order_by: [asc: h.url, asc: h.referrer])

  test "hits are buffered, then stored as daily totals per URL and referrer" do
    miss("/old/page", "https://example.com/blog?utm_source=x#top")
    miss("/old/page", "https://example.com/blog")
    miss("/old/page")

    assert rows() == []
    assert FourOhFour.flush() == 2

    today = Date.utc_today()

    assert [
             %NotFoundHit{url: "/old/page", referrer: "", date: ^today, hits: 1},
             %NotFoundHit{url: "/old/page", referrer: "https://example.com/blog", date: ^today, hits: 2}
           ] = rows()

    # Later flushes add to the same rows.
    miss("/old/page", "https://example.com/blog")
    assert FourOhFour.flush() == 1
    assert FourOhFour.flush() == 0

    assert [%{hits: 1}, %{hits: 3}] = rows()
  end

  # Audit F45: one unstorable row took the whole flush with it
  describe "an unstorable hit costs only itself" do
    test "an invalid referrer is stored as no referrer, beside a genuine hit" do
      miss("/genuine", "https://example.com/a")
      miss("/crafted", "https://example.com/" <> <<0xFF>>)
      miss("/nul", "https://example.com/" <> <<0>>)

      assert FourOhFour.flush() == 3

      assert [
               %NotFoundHit{url: "/crafted", referrer: ""},
               %NotFoundHit{url: "/genuine", referrer: "https://example.com/a"},
               %NotFoundHit{url: "/nul", referrer: ""}
             ] = rows()
    end

    test "long multibyte URLs and referrers fit the unique index" do
      # Varied, so the index cannot compress them to fit
      long =
        :rand.seed_s(:exsss, 45)
        |> then(
          &Enum.map_reduce(1..1000, &1, fn _, seed ->
            {n, seed} = :rand.uniform_s(0xFFFF, seed)
            {<<0x10000 + n::utf8>>, seed}
          end)
        )
        |> elem(0)
        |> Enum.join()

      miss("/genuine")
      miss("/" <> long, "https://example.com/" <> long)
      miss("/" <> long, "https://cms.example.com/" <> long)

      assert FourOhFour.flush() == 3
      assert length(rows()) == 3
      assert Enum.all?(rows(), &(String.valid?(&1.url) and String.valid?(&1.referrer)))
    end

    test "a row the database refuses is retried alone, so the others are stored" do
      key = fn url, referrer -> {url, referrer, Date.utc_today()} end
      Cachex.incr(:four_oh_four, key.("/genuine", ""), 2)
      Cachex.incr(:four_oh_four, key.("/refused\0", ""), 1)
      Cachex.incr(:four_oh_four, key.("/also-genuine", ""), 1)

      assert FourOhFour.flush() == 2
      assert [%{url: "/also-genuine", hits: 1}, %{url: "/genuine", hits: 2}] = rows()
    end

    test "a row the driver cannot encode is retried alone too" do
      key = fn url -> {url, "", Date.utc_today()} end
      Cachex.incr(:four_oh_four, key.("/genuine"), 2)
      Cachex.incr(:four_oh_four, key.("/unencodable"), 2 ** 70)

      assert FourOhFour.flush() == 1
      assert [%{url: "/genuine", hits: 2}] = rows()
    end

    test "a table that is not there is no row's fault: one attempt, one line in the log" do
      key = fn url -> {:tenant, "tenant_no-such_production", {url, "", Date.utc_today()}} end
      Cachex.incr(:four_oh_four, key.("/a"), 1)
      Cachex.incr(:four_oh_four, key.("/b"), 1)
      Cachex.incr(:four_oh_four, key.("/c"), 1)

      log = warnings_of(fn -> assert FourOhFour.flush() == 0 end)

      assert length(String.split(log, "404 log:")) == 2
    end

    test "a lost connection gives up on the flush with one line in the log" do
      miss("/a")
      miss("/b")

      %{rows: [[backend]]} = Ecto.Adapters.SQL.query!(Brando.Repo.repo(), "SELECT pg_backend_pid()")

      fn ->
        Ecto.Adapters.SQL.Sandbox.unboxed_run(Brando.Repo.repo(), fn ->
          Ecto.Adapters.SQL.query!(Brando.Repo.repo(), "SELECT pg_terminate_backend($1)", [backend])
        end)
      end
      |> Task.async()
      |> Task.await()

      log = warnings_of(fn -> assert FourOhFour.flush() == 0 end)

      assert length(String.split(log, "404 log:")) == 2
      assert log =~ "could not store 2 rows"
    end
  end

  # The log cuts by bytes as well: this is 601 characters, stored cut to 500.
  test "a long multibyte URL the log cut short becomes a rule for every path it begins" do
    path = "/" <> String.duplicate("ø", 600)
    miss(path)
    assert FourOhFour.flush() == 1

    assert [%{url: url}] = rows()
    assert byte_size(url) < byte_size(path)
    assert String.starts_with?(path, url)

    source = Brando.Sites.Redirects.not_found_source(url)
    refute String.ends_with?(source, "$")
    assert Regex.match?(Regex.compile!("^" <> source, "u"), path)
  end

  test "list/0 flushes, totals each URL and names the referrer that sent most hits" do
    Brando.Repo.insert!(%NotFoundHit{
      url: "/moved",
      referrer: "https://old.example.com/links",
      date: Date.add(Date.utc_today(), -3),
      hits: 5,
      last_hit_at: ~U[2026-01-01 10:00:00Z]
    })

    miss("/moved", "https://news.example.com/story")
    miss("/moved")
    miss("/rare")

    assert [moved, rare] = FourOhFour.list()

    assert moved.url == "/moved"
    assert moved.hits == 7
    assert moved.referrer == "https://old.example.com/links"
    assert is_binary(moved.last_hit_at)

    assert rare == Map.merge(rare, %{url: "/rare", hits: 1, referrer: nil, probe: false})
  end

  # Scanners send the URL they probe as its referrer, from any host
  test "a self-referrer is never the named referrer, and folds a URL it mostly sent as a probe" do
    for _ <- 1..3, do: miss("/wrangler.toml", "http://bielkeyang.com/wrangler.toml")
    for _ <- 1..3, do: miss("/blog", "http://bielkeyang.com/blog/")
    miss("/blog", "https://64.227.71.155/blog")
    miss("/blog")
    miss("/team", "http://ghost-rider/team")
    miss("/team", "https://www.bielkeyang.com/team?ref=x")
    miss("/team")
    for _ <- 1..2, do: miss("/projects/old", "https://news.example.com/story")
    miss("/projects/old", "https://bielkeyang.com/projects/old")
    miss("/projects/old", "https://bielkeyang.com/projects/old/")
    miss("/assets/app-4f9a1c.js", "https://bielkeyang.com/assets/app-4f9a1c.js")
    miss("/assets/app-4f9a1c.js")
    miss("/about", "https://bielkeyang.com/about")
    miss("/about", "https://bielkeyang.com/")

    by_url = Map.new(FourOhFour.list(), &{&1.url, &1})

    # A probe by path, and by its referrers
    assert %{probe: true, referrer: nil} = by_url["/wrangler.toml"]
    # 4 of 5 hits self-referred, only by path
    assert %{probe: true, referrer: nil} = by_url["/blog"]
    assert %{probe: true, referrer: nil} = by_url["/team"]
    # Half or fewer are not "mostly": the real referrer is named instead
    assert %{probe: false, referrer: "https://news.example.com/story"} = by_url["/projects/old"]
    assert %{probe: false, referrer: nil} = by_url["/assets/app-4f9a1c.js"]
    assert %{probe: false, referrer: "https://bielkeyang.com/"} = by_url["/about"]
  end

  test "remove/1 forgets a URL in the database and in the buffer" do
    miss("/gone")
    FourOhFour.flush()
    miss("/gone")
    miss("/kept")

    assert FourOhFour.remove("/gone") == :ok

    assert Enum.map(FourOhFour.list(), & &1.url) == ["/kept"]
  end

  test "purge/1 deletes days past the retention period" do
    for days_ago <- [0, 30, 120] do
      Brando.Repo.insert!(%NotFoundHit{
        url: "/day-#{days_ago}",
        date: Date.add(Date.utc_today(), -days_ago),
        hits: 1,
        last_hit_at: DateTime.truncate(DateTime.utc_now(), :second)
      })
    end

    assert FourOhFour.purge(90) == 1
    assert Enum.map(rows(), & &1.url) == ["/day-0", "/day-30"]
  end

  test "the flusher writes what is buffered when it stops" do
    pid = start_supervised!({FourOhFour.Flusher, :timer.hours(1)})
    Ecto.Adapters.SQL.Sandbox.allow(Brando.Repo.repo(), self(), pid)

    miss("/before-deploy")
    stop_supervised!(FourOhFour.Flusher)

    assert [%{url: "/before-deploy", hits: 1}] = rows()
  end

  # The logged URL keeps its escapes, as the request had them
  test "an escaped URL is its own referrer, however long its path" do
    for _ <- 1..2, do: miss("/bl%C3%A5b%C3%A6r", "https://site.no/bl%C3%A5b%C3%A6r")
    long = "/" <> String.duplicate("a", 600)
    for _ <- 1..2, do: miss(long, "https://example.com#{long}?q=1")
    miss("/x", "https://" <> String.duplicate("h", 2000) <> ".com/x")
    # A 3-byte character host must not push the row past the index's byte limit
    path = "/" <> String.duplicate("b", 999)
    miss(path, "https://" <> String.duplicate("語", 600) <> path)

    by_url = Map.new(FourOhFour.list(), &{&1.url, &1})

    assert %{probe: true, referrer: nil} = by_url["/bl%C3%A5b%C3%A6r"]
    assert %{probe: true, referrer: nil} = by_url[long]
    assert %{probe: true, referrer: nil} = by_url["/x"]
    assert %{probe: true, referrer: nil} = by_url[path]
    assert Enum.all?(rows(), &(byte_size(&1.referrer) <= 500 + byte_size(&1.url)))
  end

  test "a referrer that is not a web page is not stored" do
    miss("/x", "android-app://com.example")
    FourOhFour.flush()

    assert [%{referrer: ""}] = rows()
  end
end

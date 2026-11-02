defmodule Brando.Sites.FourOhFourLogTest do
  # The buffer is one global cache.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Ecto.Query, only: [from: 2]

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

  describe "the row cap" do
    defp stored(url, hits, last_hit_at) do
      Brando.Repo.insert!(%NotFoundHit{url: url, date: Date.utc_today(), hits: hits, last_hit_at: last_hit_at})
    end

    test "a flush past the cap deletes the least recently hit, and keeps what it wrote" do
      put_test_env(FourOhFour, max_rows: 3)
      stored("/followed-before", 40, ~U[2026-01-01 10:00:00Z])
      stored("/once-recent", 1, ~U[2026-01-03 10:00:00Z])
      stored("/recent", 2, ~U[2026-01-02 10:00:00Z])

      miss("/new")

      assert FourOhFour.flush() == 1
      assert rows() |> Enum.map(& &1.url) |> Enum.sort() == ["/new", "/once-recent", "/recent"]
    end

    test "a flood of new URLs stays at the cap and keeps the list working" do
      put_test_env(FourOhFour, max_rows: 10)

      for n <- 1..25, do: miss("/flood/#{n}")
      assert FourOhFour.flush() == 25
      assert length(rows()) == 10

      # A link people follow comes back with its next hit
      miss("/followed")
      assert "/followed" in Enum.map(FourOhFour.list(), & &1.url)
      assert length(rows()) == 10
    end

    test "rows with many hits or referrers do not keep a new link out" do
      put_test_env(FourOhFour, max_rows: 2)
      stored("/flood/1", 50, ~U[2026-01-01 10:00:00Z])
      stored("/flood/2", 50, ~U[2026-01-01 10:00:00Z])

      Brando.Repo.insert!(%NotFoundHit{
        url: "/flood/1",
        referrer: "https://a.example/",
        date: Date.utc_today(),
        hits: 50,
        last_hit_at: ~U[2026-01-01 10:00:00Z]
      })

      miss("/new")
      FourOhFour.flush()

      assert "/new" in Enum.map(rows(), & &1.url)
      assert length(rows()) == 2
    end

    test "a table far past the cap comes down one batch a flush" do
      put_test_env(FourOhFour, max_rows: 1)
      now = ~U[2026-01-01 10:00:00Z]
      today = Date.utc_today()
      entries = for n <- 1..10_050, do: %{url: "/old/#{n}", referrer: "", date: today, hits: 1, last_hit_at: now}

      entries |> Enum.chunk_every(1000) |> Enum.each(&Brando.Repo.insert_all(NotFoundHit, &1))

      miss("/new")
      FourOhFour.flush()
      assert Brando.Repo.aggregate(NotFoundHit, :count) == 51

      miss("/newer")
      FourOhFour.flush()
      assert Brando.Repo.aggregate(NotFoundHit, :count) == 1
      assert [%{url: "/newer"}] = rows()
    end

    test "under the cap a flush deletes nothing" do
      put_test_env(FourOhFour, max_rows: 3)
      stored("/a", 1, ~U[2026-01-01 10:00:00Z])
      stored("/b", 1, ~U[2026-01-01 10:00:00Z])

      miss("/c")

      assert FourOhFour.flush() == 1
      assert length(rows()) == 3
    end

    test "each tenant has its own cap" do
      put_test_env(FourOhFour, max_rows: 2)

      for schema <- ~w(tenant_nv404a_production tenant_nv404b_production) do
        Ecto.Adapters.SQL.query!(Brando.repo(), ~s(CREATE SCHEMA "#{schema}"))

        Ecto.Adapters.SQL.query!(
          Brando.repo(),
          ~s|CREATE TABLE "#{schema}".sites_not_found_hits (LIKE public.sites_not_found_hits INCLUDING ALL)|
        )
      end

      hit = fn prefix, url ->
        key = Brando.Tenant.cache_key({url, "", Date.utc_today()}, prefix)
        Cachex.incr(:four_oh_four, key, 1)
      end

      for n <- 1..4, do: hit.("tenant_nv404a_production", "/a/#{n}")
      hit.("tenant_nv404b_production", "/b/1")
      stored("/public", 1, ~U[2026-01-01 10:00:00Z])

      assert FourOhFour.flush() == 5

      assert Brando.Repo.aggregate(NotFoundHit, :count, prefix: "tenant_nv404a_production") == 2
      assert Brando.Repo.aggregate(NotFoundHit, :count, prefix: "tenant_nv404b_production") == 1
      assert [%{url: "/public"}] = rows()
    end

    test "the default leaves room for a real site's log" do
      assert FourOhFour.max_rows() == 100_000
    end
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

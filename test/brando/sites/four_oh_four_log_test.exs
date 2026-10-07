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

    assert rare == Map.merge(rare, %{url: "/rare", hits: 1, referrer: nil})
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

  test "a referrer that is not a web page is not stored" do
    miss("/x", "android-app://com.example")
    FourOhFour.flush()

    assert [%{referrer: ""}] = rows()
  end
end

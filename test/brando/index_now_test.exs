defmodule Brando.IndexNowTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Brando.Test.Support, only: [put_test_env: 2]

  alias Brando.ContentEvents.Event
  alias Brando.IndexNow
  alias Brando.Worker.IndexNowSubmission

  defp event(type, url, status \\ "published") do
    %Event{id: Ecto.UUID.generate(), type: type, occurred_at: DateTime.utc_now(), url: url, status: status}
  end

  defp stub(fun) do
    test = self()

    Req.Test.stub(IndexNow, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {:indexnow, Jason.decode!(body)})
      fun.(conn)
    end)
  end

  defp manual(fun), do: Oban.Testing.with_testing_mode(:manual, fun)

  test "off by default: nothing is queued and no key is served" do
    refute IndexNow.settings().enabled

    manual(fn ->
      assert :ok = IndexNow.handle_event(event("entry.published", "http://localhost/about"))
      refute_enqueued(worker: IndexNowSubmission)
    end)

    conn = Brando.Plug.IndexNow.call(Plug.Test.conn(:get, "/#{String.duplicate("a", 32)}.txt"), [])
    refute conn.halted
  end

  test "turning it on creates a key, served at /<key>.txt while it is on" do
    {:ok, settings} = IndexNow.enable()
    assert settings.key =~ ~r/^[a-f0-9]{32}$/

    conn = Brando.Plug.IndexNow.call(Plug.Test.conn(:get, "/#{settings.key}.txt"), [])
    assert conn.halted
    assert conn.status == 200
    assert conn.resp_body == settings.key
    assert ["text/plain" <> _] = Plug.Conn.get_resp_header(conn, "content-type")

    refute Brando.Plug.IndexNow.call(Plug.Test.conn(:get, "/#{IndexNow.generate_key()}.txt"), []).halted

    # Off again: the key is kept for next time, but not served.
    {:ok, off} = IndexNow.disable()
    assert off.key == settings.key
    refute Brando.Plug.IndexNow.call(Plug.Test.conn(:get, "/#{settings.key}.txt"), []).halted
    {:ok, on} = IndexNow.enable()
    assert on.key == settings.key
  end

  test "published, updated while published, unpublished and deleted entries are batched into one job" do
    {:ok, _} = IndexNow.enable()

    manual(fn ->
      for {type, status, path} <- [
            {"entry.published", "published", "/a"},
            {"entry.updated", "published", "/b"},
            {"entry.unpublished", "draft", "/c"},
            {"entry.deleted", "published", "/d"},
            {"entry.restored", "published", "/e"},
            # Repeats and the rest add nothing
            {"entry.published", "published", "/a"},
            {"entry.updated", "draft", "/draft"},
            {"entry.created", "published", "/created"}
          ] do
        assert :ok = IndexNow.handle_event(event(type, "http://localhost" <> path, status))
      end

      assert :ok = IndexNow.handle_event(event("entry.published", nil))

      assert [%Oban.Job{args: %{"urls" => urls}, scheduled_at: at}] = all_enqueued(worker: IndexNowSubmission)
      assert Enum.sort(urls) == Enum.map(~w(/a /b /c /d /e), &("http://localhost" <> &1))
      assert DateTime.diff(at, DateTime.utc_now()) in 50..60
    end)
  end

  test "a batch is one request per host, with the key and its location" do
    {:ok, settings} = IndexNow.enable()
    stub(&Plug.Conn.send_resp(&1, 202, ""))

    assert :ok =
             IndexNow.submit([
               "https://example.com/a",
               "https://example.com/b",
               "https://other.example.com/c",
               "https://example.com/a"
             ])

    assert_received {:indexnow,
                     %{"host" => "example.com", "urlList" => ["https://example.com/a", "https://example.com/b"]} = body}

    assert body["key"] == settings.key
    assert body["keyLocation"] == "https://example.com/#{settings.key}.txt"
    assert_received {:indexnow, %{"host" => "other.example.com", "urlList" => ["https://other.example.com/c"]}}

    recorded = IndexNow.settings()
    assert recorded.last_status == 202
    assert recorded.last_response == "Accepted"
    assert recorded.last_submitted_at
  end

  test "at most 10,000 URLs a request" do
    {:ok, _} = IndexNow.enable()
    stub(&Plug.Conn.send_resp(&1, 200, ""))

    urls = for n <- 1..(IndexNow.max_urls() + 1), do: "https://example.com/#{n}"
    assert :ok = IndexNow.submit(urls)

    assert_received {:indexnow, %{"urlList" => first}}
    assert_received {:indexnow, %{"urlList" => second}}
    assert {length(first), length(second)} == {10_000, 1}
    assert IndexNow.settings().last_url_count == 1
  end

  test "throttling and server errors are tried again, other answers are recorded" do
    {:ok, _} = IndexNow.enable()

    stub(&Plug.Conn.send_resp(&1, 429, "Too Many Requests"))
    assert {:error, _} = IndexNow.submit(["https://example.com/a"])

    stub(&Plug.Conn.send_resp(&1, 422, "URLs don't belong to the host"))
    assert :ok = IndexNow.submit(["https://example.com/a"])
    assert %{last_status: 422, last_response: "URLs don't belong to the host"} = IndexNow.settings()

    # The job hands the batch over.
    stub(&Plug.Conn.send_resp(&1, 200, ""))
    assert :ok = perform_job(IndexNowSubmission, %{"urls" => ["https://example.com/a"]})
  end

  test "a deployment with IndexNow turned off in its configuration submits nothing" do
    {:ok, _} = IndexNow.enable()
    put_test_env(Brando.IndexNow, enabled: false)

    refute IndexNow.submits?()
    refute IndexNow in Brando.ContentEvents.subscribers()
    assert :ok = IndexNow.submit(["https://example.com/a"])
    refute_received {:indexnow, _}
  end

  test "publishing an entry reaches IndexNow through its content event", %{} do
    {:ok, _} = IndexNow.enable()
    stub(&Plug.Conn.send_resp(&1, 202, ""))
    put_test_env(Brando.ContentEvents, debounce_seconds: 0)
    user = Brando.Factory.insert(:random_user)

    {:ok, page} =
      Brando.Pages.create_page(
        %{title: "Indexed", uri: "indexed", language: "en", template: "default.html", status: :published},
        user
      )

    url = Brando.Blueprint.URL.resolve(page, :with_host)
    assert_received {:indexnow, %{"urlList" => [^url]}}
  end
end

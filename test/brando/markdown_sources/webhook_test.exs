defmodule Brando.MarkdownSources.WebhookTest do
  use Brando.ConnCase, async: false
  alias Brando.MarkdownSources.Delivery
  alias BrandoWeb.Plugs.GitHubMarkdownWebhook, as: Webhook
  @secret String.duplicate("s", 40)

  setup do
    Brando.MarkdownSources.RateLimiter.reset(freeze: true)
    on_exit(fn -> Brando.MarkdownSources.RateLimiter.reset() end)
    old = Application.get_env(:brando, :markdown_sources)

    Application.put_env(:brando, :markdown_sources,
      connections: %{"docs" => %{secret: @secret, repository: "acme/docs", repository_id: 42, destinations: [nil]}}
    )

    on_exit(fn ->
      if old,
        do: Application.put_env(:brando, :markdown_sources, old),
        else: Application.delete_env(:brando, :markdown_sources)
    end)

    :ok
  end

  defp payload(overrides \\ %{}),
    do:
      Jason.encode!(
        Map.merge(
          %{
            "repository" => %{"id" => 42},
            "ref" => "refs/heads/main",
            "after" => String.duplicate("a", 40),
            "deleted" => false
          },
          overrides
        )
      )

  defp signed(body, delivery \\ "12345678-1234-1234-1234-123456789012") do
    Plug.Test.conn(:post, "https://cms.example.test/api/markdown-sources/webhooks/docs", body)
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-github-event", "push")
    |> put_req_header("x-github-delivery", delivery)
    |> put_req_header(
      "x-hub-signature-256",
      "sha256=" <> Base.encode16(:crypto.mac(:hmac, :sha256, @secret, body), case: :lower)
    )
  end

  # A well-formed header, so the request is read and goes through the HMAC
  defp wrongly_signed(body, ip) do
    %{Plug.Test.conn(:post, "https://cms.example.test/api/markdown-sources/webhooks/docs", body) | remote_ip: ip}
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-hub-signature-256", "sha256=" <> String.duplicate("0", 64))
  end

  test "authenticates exact bytes and durably deduplicates both delivery IDs and body fingerprints" do
    Oban.Testing.with_testing_mode(:manual, fn ->
      body = payload()
      assert signed(body) |> Webhook.call([]) |> Map.get(:status) == 202
      assert signed(body) |> Webhook.call([]) |> Map.get(:status) == 202
      assert signed(body, "87654321-1234-1234-1234-123456789012") |> Webhook.call([]) |> Map.get(:status) == 202
      assert Repo.aggregate(Delivery, :count) == 1
      assert [%{id: job_id, args: args}] = all_enqueued(worker: Brando.Worker.MarkdownSourceSync)
      assert Repo.one!(Delivery).job_ids == [job_id]
      assert args["connection"] == "docs"
      refute Map.has_key?(args, "secret")
      refute Map.has_key?(args, "after")
    end)
  end

  test "rejects invalid, missing, ambiguous, and SHA1 signatures without enqueuing" do
    body = payload()

    for headers <- [[], ["sha256=" <> String.duplicate("0", 64)], ["sha1=abc"], ["sha256=" <> String.duplicate("z", 64)]] do
      assert Webhook.verify(headers, body, @secret) == {:error, :invalid_signature}
    end

    good = get_req_header(signed(body), "x-hub-signature-256")
    assert Webhook.verify(good ++ good, body, @secret) == {:error, :invalid_signature}
    assert Webhook.verify(good, body <> " ", @secret) == {:error, :invalid_signature}
    assert Webhook.verify(good, body, "") == {:error, :invalid_signature}
    assert signed(body) |> delete_req_header("x-hub-signature-256") |> Webhook.call([]) |> Map.get(:status) == 401
    assert Repo.aggregate(Delivery, :count) == 0
  end

  test "rejects wrong repositories, forged events, malformed JSON and oversized bodies" do
    for body <- [payload(%{"repository" => %{"id" => 666}}), "{", "[]"] do
      assert signed(body) |> Webhook.call([]) |> Map.get(:status) == 401
    end

    assert signed(payload()) |> put_req_header("x-github-event", "ping") |> Webhook.call([]) |> Map.get(:status) == 401
    assert signed(String.duplicate("x", 1_048_577)) |> Webhook.call([]) |> Map.get(:status) == 413
    assert Repo.aggregate(Delivery, :count) == 0
  end

  test "a missing or malformed signature header is refused before the body is read" do
    oversized = signed(String.duplicate("x", 1_048_577))

    assert oversized |> delete_req_header("x-hub-signature-256") |> Webhook.call([]) |> Map.get(:status) == 401

    for value <- ["sha1=abc", "sha256=" <> String.duplicate("0", 63), "sha256=" <> String.duplicate("0", 65)] do
      assert oversized |> put_req_header("x-hub-signature-256", value) |> Webhook.call([]) |> Map.get(:status) == 401
    end

    twice = update_in(oversized.req_headers, &[{"x-hub-signature-256", "sha256=" <> String.duplicate("0", 64)} | &1])
    assert twice |> Webhook.call([]) |> Map.get(:status) == 401
  end

  test "tenant routing comes only from configured destinations, never signed payload fields" do
    Oban.Testing.with_testing_mode(:manual, fn ->
      assert signed(payload(%{"tenant_prefix" => "tenant_victim_production"})) |> Webhook.call([]) |> Map.get(:status) ==
               202

      assert [%{args: args}] = all_enqueued(worker: Brando.Worker.MarkdownSourceSync)
      refute Map.has_key?(args, "tenant_prefix")
    end)
  end

  test "plain HTTP and unsupported delivery shapes fail closed" do
    conn = signed(payload())
    assert %{conn | scheme: :http} |> Webhook.call([]) |> Map.get(:status) == 401
    assert %{conn | method: "GET"} |> Webhook.call([]) |> Map.get(:status) == 401
    assert conn |> put_req_header("content-type", "text/plain") |> Webhook.call([]) |> Map.get(:status) == 401
    assert conn |> put_req_header("x-github-event", "issues") |> Webhook.call([]) |> Map.get(:status) == 401
    refute_enqueued(worker: Brando.Worker.MarkdownSourceSync)
  end

  test "chunked raw body verification covers all bytes" do
    body = payload(%{"padding" => String.duplicate("ø", 80_000)})

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert signed(body) |> Webhook.call([]) |> Map.get(:status) == 202
    end)
  end

  # Audit F23: unsigned requests used up the node-wide budget before the
  # signature was checked, and a limited delivery got 401
  describe "rate limits" do
    defp unsigned(ip) do
      %{Plug.Test.conn(:post, "https://cms.example.test/api/markdown-sources/webhooks/docs", "{}") | remote_ip: ip}
      |> put_req_header("content-type", "application/json")
    end

    test "unsigned requests from many addresses leave the budget for signed deliveries" do
      for i <- 1..1_300 do
        ip = {10, 1, div(i, 250), rem(i, 250)}
        assert unsigned(ip) |> Webhook.call([]) |> Map.get(:status) == 401
      end

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert payload() |> signed() |> Webhook.call([]) |> Map.get(:status) == 202
      end)
    end

    test "one address over its budget gets 429, and others are not held back" do
      for _ <- 1..120, do: assert(unsigned({192, 0, 2, 1}) |> Webhook.call([]) |> Map.get(:status) == 401)

      conn = unsigned({192, 0, 2, 1}) |> Webhook.call([])
      assert conn.status == 429
      assert Jason.decode!(conn.resp_body) == %{"status" => "rate_limited"}

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert payload() |> signed() |> Webhook.call([]) |> Map.get(:status) == 202
      end)
    end

    test "one client over its budget does not fill the node's cap" do
      for _ <- 1..12_100, do: unsigned({192, 0, 2, 1}) |> Webhook.call([])

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert payload() |> signed() |> Webhook.call([]) |> Map.get(:status) == 202
      end)
    end

    test "each client has a budget of its own" do
      for _ <- 1..120, do: unsigned({192, 0, 2, 1}) |> Webhook.call([])

      for i <- 2..200 do
        assert unsigned({192, 0, 2, i}) |> Webhook.call([]) |> Map.get(:status) == 401
      end
    end

    test "an IPv6 client is counted by its /64" do
      for i <- 1..120 do
        assert unsigned({0x2001, 0xDB8, 0, 1, 0, 0, 0, i}) |> Webhook.call([]) |> Map.get(:status) == 401
      end

      assert unsigned({0x2001, 0xDB8, 0, 1, 0xFFFF, 0, 0, 1}) |> Webhook.call([]) |> Map.get(:status) == 429
      assert unsigned({0x2001, 0xDB8, 0, 2, 0, 0, 0, 1}) |> Webhook.call([]) |> Map.get(:status) == 401
    end

    test "clients behind a trusted proxy are counted by their own address" do
      proxied = fn client ->
        unsigned({127, 0, 0, 1}) |> put_req_header("x-forwarded-for", client) |> Webhook.call([])
      end

      for _ <- 1..120, do: assert(proxied.("203.0.113.9").status == 401)
      assert proxied.("203.0.113.9").status == 429
      assert proxied.("198.51.100.7").status == 401
    end
  end

  # Audit F34: requests nobody signed filled the node-wide cap, and signed
  # deliveries were refused with them until the next minute
  describe "over the node's cap" do
    alias Brando.MarkdownSources.RateLimiter

    # A hundred IPv6 /64s at their limit, without the cost of 12,000 requests
    setup do
      for prefix <- 1..100, _ <- 1..120 do
        assert RateLimiter.allow_client?({0x2001, 0xDB8, 0xF, prefix, 0, 0, 0, 1}, true)
      end

      :ok
    end

    defp unsigned_to(key, ip) do
      %{Plug.Test.conn(:post, "https://cms.example.test/api/markdown-sources/webhooks/#{key}", "{}") | remote_ip: ip}
      |> put_req_header("content-type", "application/json")
    end

    test "a signed delivery is accepted, and an unsigned one for a known key is rejected as unsigned" do
      assert unsigned({192, 0, 2, 50}) |> Webhook.call([]) |> Map.get(:status) == 401

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert payload() |> signed() |> Webhook.call([]) |> Map.get(:status) == 202
        assert [_job] = all_enqueued(worker: Brando.Worker.MarkdownSourceSync)
      end)
    end

    test "a signed delivery is accepted while wrongly signed ones for its key are in flight" do
      flood =
        for i <- 1..200 do
          Task.async(fn ->
            wrongly_signed(String.duplicate("x", 200_000), {198, 51, 100, i})
            |> Webhook.call([])
            |> Map.get(:status)
          end)
        end

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert payload() |> signed() |> Webhook.call([]) |> Map.get(:status) == 202
      end)

      assert flood |> Task.await_many(30_000) |> Enum.uniq() == [401]
    end

    test "a client over its own budget is still refused" do
      for _ <- 1..120, do: assert(unsigned({192, 0, 2, 51}) |> Webhook.call([]) |> Map.get(:status) == 401)
      assert unsigned({192, 0, 2, 51}) |> Webhook.call([]) |> Map.get(:status) == 429
    end

    test "a request for an unknown key costs nothing to refuse and is not tracked" do
      before = map_size(:sys.get_state(RateLimiter).clients)
      assert unsigned_to("nope", {192, 0, 2, 52}) |> Webhook.call([]) |> Map.get(:status) == 429
      assert map_size(:sys.get_state(RateLimiter).clients) == before
    end
  end

  test "a request for an unknown key under the cap is rejected" do
    conn =
      %{
        Plug.Test.conn(:post, "https://cms.example.test/api/markdown-sources/webhooks/nope", "{}")
        | remote_ip: {192, 0, 2, 53}
      }
      |> put_req_header("content-type", "application/json")

    assert conn |> Webhook.call([]) |> Map.get(:status) == 401
  end

  test "past the cap a client not counted before is refused after its budget, however many are tracked" do
    alias Brando.MarkdownSources.RateLimiter

    :sys.replace_state(RateLimiter, fn state ->
      %{state | requests: 12_000, clients: Map.new(1..200_000, &{{&1}, 1})}
    end)

    address = {192, 0, 2, 54}
    for _ <- 1..120, do: assert(RateLimiter.allow_client?(address, true))
    refute RateLimiter.allow_client?(address, true)
  end

  test "a busy signature check makes a request wait, and does not refuse it" do
    alias Brando.MarkdownSources.SignatureCheck

    :sys.suspend(SignatureCheck)
    on_exit(fn -> :sys.resume(SignatureCheck) end)

    task = Task.async(fn -> wrongly_signed("{}", {192, 0, 2, 55}) |> Webhook.call([]) |> Map.get(:status) end)
    assert Task.yield(task, 200) == nil

    :sys.resume(SignatureCheck)
    assert Task.await(task) == 401
  end
end

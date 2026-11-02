defmodule Brando.MarkdownSources.WebhookTest do
  use Brando.ConnCase, async: false
  alias Brando.MarkdownSources.{Delivery, ReadSlots}
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

  # #3399: GitHub sends every customer's webhooks from the same addresses, so
  # anyone's wrongly signed requests counted against the address genuine
  # deliveries come from, and past 120 a minute refused them
  describe "GitHub's webhook addresses" do
    alias Brando.MarkdownSources.{GitHubAddresses, RateLimiter}

    @github {192, 30, 252, 10}

    defmodule Meta do
      def meta(url) do
        send(Application.get_env(:brando, :github_meta_test_pid), {:meta, url})
        {:ok, %{"hooks" => ["192.30.252.0/22", "2606:50c0::/32"]}}
      end
    end

    defp with_ranges(ranges) do
      Application.put_env(
        :brando,
        :markdown_sources,
        Keyword.put(Application.get_env(:brando, :markdown_sources), :github_hook_ranges, ranges)
      )
    end

    test "wrongly signed requests past 120 a minute leave a correctly signed delivery from the same address through" do
      with_ranges(["192.30.252.0/22"])

      for _ <- 1..150, do: assert(wrongly_signed("{}", @github) |> Webhook.call([]) |> Map.get(:status) == 401)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert %{signed(payload()) | remote_ip: @github} |> Webhook.call([]) |> Map.get(:status) == 202
      end)
    end

    test "an address in the ranges has a budget of 1,200 a minute, and one outside them 120" do
      with_ranges(["192.30.252.0/22", "2606:50c0::/32"])

      for _ <- 1..1_200, do: assert(RateLimiter.allow_client?(@github, true, true))
      assert wrongly_signed("{}", @github) |> Webhook.call([]) |> Map.get(:status) == 429

      v6 = {0x2606, 0x50C0, 0, 1, 0, 0, 0, 1}
      for _ <- 1..121, do: assert(wrongly_signed("{}", v6) |> Webhook.call([]) |> Map.get(:status) == 401)

      outside = {192, 30, 251, 10}
      for _ <- 1..120, do: assert(wrongly_signed("{}", outside) |> Webhook.call([]) |> Map.get(:status) == 401)
      assert wrongly_signed("{}", outside) |> Webhook.call([]) |> Map.get(:status) == 429
    end

    test "with no list, GitHub's addresses have the ordinary budget" do
      with_ranges([])

      for _ <- 1..120, do: assert(wrongly_signed("{}", @github) |> Webhook.call([]) |> Map.get(:status) == 401)
      assert wrongly_signed("{}", @github) |> Webhook.call([]) |> Map.get(:status) == 429
    end

    test "the list fetched from GitHub's /meta API gives its addresses the larger budget, and requests fetch nothing" do
      Application.put_env(:brando, :github_meta_test_pid, self())
      on_exit(fn -> Application.delete_env(:brando, :github_meta_test_pid) end)
      on_exit(fn -> :persistent_term.erase({GitHubAddresses, GitHubAddresses}) end)

      pid = start_supervised!({GitHubAddresses, client: Meta})
      :sys.get_state(pid)
      assert_received {:meta, "https://api.github.com/meta"}

      for _ <- 1..150, do: assert(wrongly_signed("{}", @github) |> Webhook.call([]) |> Map.get(:status) == 401)
      refute_received {:meta, _}

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert %{signed(payload()) | remote_ip: @github} |> Webhook.call([]) |> Map.get(:status) == 202
      end)
    end

    test "requests from GitHub's addresses are read holding a slot, and wait for one" do
      with_ranges(["192.30.252.0/22"])
      holders = hold_slots(16)

      waiting =
        Task.async(fn ->
          Oban.Testing.with_testing_mode(:manual, fn ->
            %{signed(payload()) | remote_ip: @github} |> Webhook.call([]) |> Map.get(:status)
          end)
        end)

      assert Task.yield(waiting, 200) == nil
      # A request from another address does not wait
      assert wrongly_signed("{}", {192, 0, 2, 60}) |> Webhook.call([]) |> Map.get(:status) == 401

      Process.exit(hd(holders), :kill)
      assert Task.await(waiting) == 202
      Enum.each(holders, &send(&1, :release))
    end

    test "a delivery from GitHub's addresses holds its slot until it is accepted" do
      with_ranges(["192.30.252.0/22"])
      :telemetry.attach("stall-acceptance", [:oban, :engine, :insert_job, :start], &__MODULE__.stall/4, self())
      on_exit(fn -> :telemetry.detach("stall-acceptance") end)
      hold_slots(15)

      accepting =
        Task.async(fn ->
          Process.put(:stall_acceptance, true)

          Oban.Testing.with_testing_mode(:manual, fn ->
            %{signed(payload()) | remote_ip: @github} |> Webhook.call([]) |> Map.get(:status)
          end)
        end)

      assert_receive {:stalled, stalled}, 5_000

      # A ping writes nothing, so only a slot can hold it back
      ping = Jason.encode!(%{"repository" => %{"id" => 42}, "zen" => "Keep it logically awesome."})

      waiting =
        Task.async(fn ->
          %{signed(ping) | remote_ip: @github} |> put_req_header("x-github-event", "ping") |> Webhook.call([])
        end)

      assert Task.yield(waiting, 200) == nil
      send(stalled, :go)
      assert Task.await(accepting) == 202
      assert Task.await(waiting).status == 202
    end

    test "a request given a slot late has the whole window to send its body" do
      with_ranges(["192.30.252.0/22"])
      [first | _] = hold_slots(16)
      conn = %{signed(payload()) | remote_ip: @github} |> slow_body(1_000)

      request =
        Task.async(fn ->
          Oban.Testing.with_testing_mode(:manual, fn ->
            conn |> Webhook.call(body_timeout: 2_000) |> Map.get(:status)
          end)
        end)

      Process.sleep(1_200)
      Process.exit(first, :kill)
      assert Task.await(request) == 202
    end
  end

  def stall(_event, _measurements, _metadata, test) do
    if Process.get(:stall_acceptance) do
      send(test, {:stalled, self()})
      receive do: (:go -> :ok)
    end
  end

  defp hold_slots(count) do
    parent = self()

    holders =
      for _ <- 1..count, do: spawn(fn -> ReadSlots.run(System.monotonic_time(:millisecond) + 5_000, hold(parent)) end)

    for _ <- 1..count, do: assert_receive(:holding)
    on_exit(fn -> Enum.each(holders, &Process.exit(&1, :kill)) end)
    holders
  end

  defp hold(parent) do
    fn ->
      send(parent, :holding)
      receive do: (:release -> :ok)
    end
  end

  # A client that sends its body slowly: a read given less than `needs`
  # milliseconds times out
  defmodule SlowBody do
    def read_req_body({inner, needs}, opts) do
      if opts[:read_timeout] >= needs do
        {status, data, inner} = Plug.Adapters.Test.Conn.read_req_body(inner, opts)
        {status, data, {inner, needs}}
      else
        {:error, :timeout}
      end
    end

    def send_resp({inner, needs}, status, headers, body) do
      {:ok, sent, inner} = Plug.Adapters.Test.Conn.send_resp(inner, status, headers, body)
      {:ok, sent, {inner, needs}}
    end
  end

  defp slow_body(%{adapter: {Plug.Adapters.Test.Conn, inner}} = conn, needs),
    do: %{conn | adapter: {SlowBody, {inner, needs}}}

  describe "the signature check" do
    alias Brando.MarkdownSources.SignatureCheck

    @github {192, 30, 252, 10}

    setup do
      Application.put_env(
        :brando,
        :markdown_sources,
        Keyword.put(Application.get_env(:brando, :markdown_sources), :github_hook_ranges, ["192.30.252.0/22"])
      )

      :ok
    end

    # A slow check holding the turn until released
    defp hold_check do
      parent = self()

      holder =
        spawn(fn ->
          SignatureCheck.run(fn ->
            send(parent, {:checking, self()})
            receive do: (:release -> :ok)
          end)
        end)

      assert_receive {:checking, checking}

      on_exit(fn ->
        send(checking, :release)
        Process.exit(holder, :kill)
      end)

      checking
    end

    # Checks from other addresses in line, each taking `ms`
    defp flood(count, ms) do
      for _ <- 1..count do
        pid = spawn(fn -> SignatureCheck.run(fn -> Process.sleep(ms) end) end)
        on_exit(fn -> Process.exit(pid, :kill) end)
        Process.sleep(5)
      end
    end

    defp wait_until(check, tries \\ 400) do
      cond do
        check.() ->
          :ok

        tries == 0 ->
          flunk("condition not met in time")

        true ->
          Process.sleep(5)
          wait_until(check, tries - 1)
      end
    end

    defp deliver(conn, opts) do
      Task.async(fn ->
        Oban.Testing.with_testing_mode(:manual, fn -> conn |> Webhook.call(opts) |> Map.get(:status) end)
      end)
    end

    test "a busy check makes a request wait, and does not refuse it" do
      checking = hold_check()

      task = Task.async(fn -> wrongly_signed("{}", {192, 0, 2, 55}) |> Webhook.call([]) |> Map.get(:status) end)
      assert Task.yield(task, 200) == nil

      send(checking, :release)
      assert Task.await(task) == 401
    end

    test "a check that raises, or whose process dies, gives the turn back" do
      assert_raise RuntimeError, fn -> SignatureCheck.run(fn -> raise "check failed" end) end

      checking = hold_check()
      Process.exit(checking, :kill)
      assert SignatureCheck.run(fn -> :ran end, deadline: System.monotonic_time(:millisecond) + 1_000) == :ran
    end

    test "a request waiting past its deadline gets 429 and gives back its read slot" do
      checking = hold_check()

      task = deliver(%{signed(payload()) | remote_ip: @github}, body_timeout: 300)
      assert Task.yield(task, 2_000) == {:ok, 429}
      # The read slot comes back by a cast from the request's process
      wait_until(fn -> :sys.get_state(ReadSlots).free == 16 end)

      send(checking, :release)
      assert %{waiting: waiting} = :sys.get_state(SignatureCheck)
      assert waiting == %{}
    end

    test "a flood from other addresses does not hold back a delivery from GitHub's" do
      checking = hold_check()
      flood(20, 100)

      task = deliver(%{signed(payload()) | remote_ip: @github}, body_timeout: 1_000)
      Process.sleep(50)
      send(checking, :release)

      assert Task.yield(task, 1_500) == {:ok, 202}
    end

    test "a request from another address waits its turn in the flood, up to its deadline" do
      checking = hold_check()
      flood(20, 100)

      task = deliver(%{signed(payload()) | remote_ip: {192, 0, 2, 56}}, body_timeout: 500)
      Process.sleep(50)
      send(checking, :release)

      assert Task.yield(task, 1_500) == {:ok, 429}
    end
  end
end

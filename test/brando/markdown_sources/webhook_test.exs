defmodule Brando.MarkdownSources.WebhookTest do
  use Brando.ConnCase, async: false
  alias BrandoWeb.Plugs.GitHubMarkdownWebhook, as: Webhook
  alias Brando.MarkdownSources.Delivery
  @secret String.duplicate("s", 40)

  setup do
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
end

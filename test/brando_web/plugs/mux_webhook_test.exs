defmodule BrandoWeb.Plugs.MuxWebhookTest do
  use ExUnit.Case, async: true

  alias BrandoWeb.Plugs.MuxWebhook

  @secret "mux-webhook-secret"
  @body ~s({"type":"video.asset.ready","data":{"id":"asset-id"}})
  @now 1_720_000_000

  test "accepts Mux's HMAC over timestamp dot exact raw body" do
    assert :ok = MuxWebhook.verify_signature(signed(@body, @now), @body, @secret, @now)
  end

  test "rejects a missing header and an unconfigured secret" do
    assert {:error, :invalid_signature} = MuxWebhook.verify_signature(nil, @body, @secret, @now)

    assert {:error, :invalid_signature} =
             MuxWebhook.verify_signature(signed(@body, @now), @body, nil, @now)
  end

  test "rejects a signature computed over a different body" do
    assert {:error, :invalid_signature} =
             MuxWebhook.verify_signature(signed(@body, @now), @body <> " ", @secret, @now)
  end

  test "rejects a replayed delivery but accepts one inside the tolerance" do
    assert :ok = MuxWebhook.verify_signature(signed(@body, @now - 300), @body, @secret, @now)

    assert {:error, :invalid_signature} =
             MuxWebhook.verify_signature(signed(@body, @now - 301), @body, @secret, @now)

    assert {:error, :invalid_signature} =
             MuxWebhook.verify_signature(signed(@body, @now + 301), @body, @secret, @now)
  end

  test "a malformed header is rejected, never raised" do
    # The header is unauthenticated input. Each of these crashed the plug with a
    # FunctionClauseError before it had a test — a 500 where the branch beside
    # it returns 401.
    headers = [
      "",
      "nonsense",
      "t,v1",
      "t=#{@now},v1",
      "t=#{@now}",
      "v1=#{String.duplicate("a", 64)}",
      "t=notanumber,v1=#{String.duplicate("a", 64)}",
      "t=#{@now}abc,v1=#{String.duplicate("a", 64)}"
    ]

    for header <- headers do
      assert {:error, :invalid_signature} =
               MuxWebhook.verify_signature(header, @body, @secret, @now),
             "expected #{inspect(header)} to be rejected"
    end
  end

  test "a signature value containing = is data, not a parse failure" do
    assert {:error, :invalid_signature} =
             MuxWebhook.verify_signature("t=#{@now},v1=abc=def", @body, @secret, @now)
  end

  test "call/2 leaves requests outside its mount untouched" do
    conn = Plug.Test.conn(:post, "/somewhere/else", @body)
    options = MuxWebhook.init(mount: ["api", "videos", "mux", "webhook"])

    assert MuxWebhook.call(conn, options) == conn
  end

  defp signed(body, timestamp) do
    signature =
      :hmac
      |> :crypto.mac(:sha256, @secret, "#{timestamp}.#{body}")
      |> Base.encode16(case: :lower)

    "t=#{timestamp},v1=#{signature}"
  end
end

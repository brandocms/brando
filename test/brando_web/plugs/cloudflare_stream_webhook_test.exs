defmodule BrandoWeb.Plugs.CloudflareStreamWebhookTest do
  use ExUnit.Case, async: true

  import Plug.Conn

  alias BrandoWeb.Plugs.CloudflareStreamWebhook

  @secret "cloudflare-stream-webhook-secret"
  @body ~s({"uid":"video-id","readyToStream":true,"status":{"state":"ready"}})
  @now 1_720_000_000

  test "accepts Cloudflare's HMAC over timestamp dot exact raw body" do
    conn = signed_conn(@body, @now)
    assert :ok = CloudflareStreamWebhook.verify_signature(conn, @body, @secret, @now)
  end

  test "rejects missing, malformed, stale, and mismatched signatures" do
    conn = Plug.Test.conn(:post, "/", @body)

    assert {:error, :invalid_signature} =
             CloudflareStreamWebhook.verify_signature(conn, @body, @secret, @now)

    malformed = put_req_header(conn, "webhook-signature", "time=nope,sig1=abcd")

    assert {:error, :invalid_signature} =
             CloudflareStreamWebhook.verify_signature(malformed, @body, @secret, @now)

    stale = signed_conn(@body, @now - 301)

    assert {:error, :invalid_signature} =
             CloudflareStreamWebhook.verify_signature(stale, @body, @secret, @now)

    mismatched = signed_conn(@body <> " ", @now)

    assert {:error, :invalid_signature} =
             CloudflareStreamWebhook.verify_signature(mismatched, @body, @secret, @now)

    assert {:error, :invalid_signature} =
             CloudflareStreamWebhook.verify_signature(signed_conn(@body, @now), @body, nil, @now)
  end

  defp signed_conn(body, timestamp) do
    signature =
      :crypto.mac(:hmac, :sha256, @secret, "#{timestamp}.#{body}")
      |> Base.encode16(case: :lower)

    Plug.Test.conn(:post, "/", body)
    |> put_req_header("webhook-signature", "time=#{timestamp},sig1=#{signature}")
  end
end

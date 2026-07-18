defmodule BrandoWeb.Plugs.BunnyWebhookTest do
  use ExUnit.Case, async: true

  import Plug.Conn

  alias BrandoWeb.Plugs.BunnyWebhook

  @secret "bunny-read-only-api-key"
  @body ~s({"VideoLibraryId":133,"VideoGuid":"video-guid","Status":3})

  test "accepts Bunny's v1 HMAC signature over the exact raw body" do
    signature = sign(@body)

    conn =
      Plug.Test.conn(:post, "/", @body)
      |> put_req_header("x-bunnystream-signature-version", "v1")
      |> put_req_header("x-bunnystream-signature-algorithm", "hmac-sha256")
      |> put_req_header("x-bunnystream-signature", signature)

    assert :ok = BunnyWebhook.verify_signature(conn, @body, @secret)
  end

  test "rejects missing, malformed, or mismatched signature metadata" do
    conn = Plug.Test.conn(:post, "/", @body)
    assert {:error, :invalid_signature} = BunnyWebhook.verify_signature(conn, @body, @secret)

    conn =
      conn
      |> put_req_header("x-bunnystream-signature-version", "v2")
      |> put_req_header("x-bunnystream-signature-algorithm", "hmac-sha256")
      |> put_req_header("x-bunnystream-signature", sign(@body))

    assert {:error, :invalid_signature} = BunnyWebhook.verify_signature(conn, @body, @secret)

    conn =
      Plug.Test.conn(:post, "/", @body)
      |> put_req_header("x-bunnystream-signature-version", "v1")
      |> put_req_header("x-bunnystream-signature-algorithm", "hmac-sha256")
      |> put_req_header("x-bunnystream-signature", String.duplicate("0", 64))

    assert {:error, :invalid_signature} = BunnyWebhook.verify_signature(conn, @body, @secret)
    assert {:error, :invalid_signature} = BunnyWebhook.verify_signature(conn, @body, nil)
  end

  defp sign(body) do
    :crypto.mac(:hmac, :sha256, @secret, body)
    |> Base.encode16(case: :lower)
  end
end

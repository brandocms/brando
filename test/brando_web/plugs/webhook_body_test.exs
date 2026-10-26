defmodule BrandoWeb.Plugs.WebhookBodyTest do
  @moduledoc """
  The video webhook plugs read at most 1 MiB of an unauthenticated body before
  they check its signature (audit NV1). Over that they answer 413 instead of
  buffering it all (Cloudflare) or crashing on `{:more, …}` (Mux, Bunny).
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias BrandoWeb.Plugs.BunnyWebhook
  alias BrandoWeb.Plugs.CloudflareStreamWebhook
  alias BrandoWeb.Plugs.MuxWebhook
  alias BrandoWeb.Plugs.WebhookBody

  @mount ["api", "hook"]
  @plugs [CloudflareStreamWebhook, MuxWebhook, BunnyWebhook]

  defp post(plug, body) do
    capture_log(fn -> send(self(), {:conn, plug.call(Plug.Test.conn(:post, "/api/hook", body), mount: @mount)}) end)
    assert_received {:conn, conn}
    conn
  end

  test "refuses a body over the limit with 413, before any signature check" do
    body = String.duplicate("a", 1_048_577)

    for plug <- @plugs do
      conn = post(plug, body)
      assert conn.halted, inspect(plug)
      assert conn.status == 413, inspect(plug)
    end
  end

  test "reads a body up to the limit and goes on to the signature check" do
    body = String.duplicate("a", 1_048_576)

    for plug <- @plugs do
      conn = post(plug, body)
      assert conn.status == 401, inspect(plug)
    end
  end

  test "read/2 takes the limit it is given" do
    assert {:ok, "abc", _conn} = WebhookBody.read(Plug.Test.conn(:post, "/", "abc"), 3)
    assert {:halted, %{status: 413}} = WebhookBody.read(Plug.Test.conn(:post, "/", "abcd"), 3)
  end
end

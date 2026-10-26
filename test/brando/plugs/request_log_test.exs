defmodule Brando.Plug.RequestLogTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Brando.Plug.RequestLog

  defp conn(path), do: Plug.Test.conn(:get, path)

  # At :error, which the test log level lets through
  test "a path with a secret token is logged with the token filtered out" do
    for {path, logged} <- [
          {"/__p__/Zx81kQ0pLm2a", "GET /__p__/[FILTERED]"},
          {"/__ssg_preview__/c2VjcmV0dG9rZW4/about/index.html", "GET /__ssg_preview__/[FILTERED]/about/index.html"},
          {"/admin/reset-password/s3cr3t", "GET /admin/reset-password/[FILTERED]"},
          {"/cms/reset-password/s3cr3t", "GET /cms/reset-password/[FILTERED]"},
          {"/admin/content-transfer/download/s3cr3t", "GET /admin/content-transfer/download/[FILTERED]"},
          {"/admin/assistant/shared/s3cr3t", "GET /admin/assistant/shared/[FILTERED]"}
        ] do
      log = capture_log(fn -> assert RequestLog.level(conn(path), :error) == false end)
      assert log =~ logged
      refute log =~ "s3cr3t"
    end
  end

  test "the end of such a request logs nothing" do
    conn = conn("/__p__/s3cr3t") |> Plug.Conn.send_resp(200, "")
    assert capture_log(fn -> assert RequestLog.level(conn, :error) == false end) == ""
  end

  test "other paths keep the level, and log nothing here" do
    for path <- ["/", "/admin/reset-password", "/__p__", "/admin/users/1", "/projects/reset-password-tips"] do
      assert capture_log(fn -> assert RequestLog.level(conn(path), :error) == :error end) == ""
    end

    assert RequestLog.level(conn("/about"), :debug) == :debug
  end
end

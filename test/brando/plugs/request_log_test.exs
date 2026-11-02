defmodule Brando.Plug.RequestLogTest do
  use ExUnit.Case, async: true

  alias Brando.Plug.RequestLog
  alias Brando.Test.OwnLog

  defp conn(path), do: Plug.Test.conn(:get, path)

  # At :error, which the test log level lets through. Captured with
  # `OwnLog.capture/1`, since `capture_log/1` also gets what concurrent tests log.
  test "a path with a secret token is logged with the token filtered out" do
    for {path, logged} <- [
          {"/__p__/Zx81kQ0pLm2a", "GET /__p__/[FILTERED]"},
          {"/__ssg_preview__/c2VjcmV0dG9rZW4/about/index.html", "GET /__ssg_preview__/[FILTERED]/about/index.html"},
          {"/admin/reset-password/s3cr3t", "GET /admin/reset-password/[FILTERED]"},
          {"/cms/reset-password/s3cr3t", "GET /cms/reset-password/[FILTERED]"},
          {"/admin/content-transfer/download/s3cr3t", "GET /admin/content-transfer/download/[FILTERED]"},
          {"/admin/assistant/shared/s3cr3t", "GET /admin/assistant/shared/[FILTERED]"}
        ] do
      log = OwnLog.capture(fn -> assert RequestLog.level(conn(path), :error) == false end)
      assert log =~ logged
      refute log =~ "s3cr3t"
    end
  end

  # The router decodes segments before it matches them, so these open the
  # same pages (found by the Codex audit)
  test "a percent-encoded path is filtered as the router reads it" do
    for path <- ["/admin/%72eset-password/s3cr3t", "/%5f_p__/s3cr3t", "/admin/assistant/%73hared/s3cr3t"] do
      log = OwnLog.capture(fn -> assert RequestLog.level(conn(path), :error) == false end)
      assert log =~ "[FILTERED]"
      refute log =~ "s3cr3t"
    end
  end

  # Audit F38: the logged line came from the decoded segments, so an encoded line
  # feed started a line of the sender's own
  test "encoded control characters stay encoded in the logged line" do
    for {path, logged} <- [
          {"/__ssg_preview__/x/%0A10:00:00.000%20[info]%20POST%20/admin/login",
           "GET /__ssg_preview__/[FILTERED]/%0A10:00:00.000%20[info]%20POST%20/admin/login"},
          {"/a%0Ab/reset-password/s3cr3t", "GET /a%0Ab/reset-password/[FILTERED]"},
          {"/admin/reset-password/s3cr3t/%0D%1B%FF", "GET /admin/reset-password/[FILTERED]/%0D%1B%FF"}
        ] do
      log = OwnLog.capture(fn -> assert RequestLog.level(conn(path), :error) == false end)
      assert log =~ logged
      refute log =~ "\n10:00"
      refute log =~ "s3cr3t"
    end
  end

  test "a marker sent encoded logs as sent, with the token at its index filtered" do
    assert RequestLog.filter(["admin", "%72eset-password", "s3cr3t"]) == ["admin", "%72eset-password", "[FILTERED]"]

    assert RequestLog.filter(["admin", "content-%74ransfer", "download", "s3cr3t", "x"]) ==
             ["admin", "content-%74ransfer", "download", "[FILTERED]", "x"]

    assert RequestLog.filter(["a", "__p__", "x"]) == nil
    assert RequestLog.filter([]) == nil
  end

  test "a path of 20,000 segments has no token" do
    assert RequestLog.filter(List.duplicate("a", 20_000)) == nil
  end

  test "a marker at the end of a long path filters the segment after it" do
    segments = List.duplicate("a", 20_000)

    assert RequestLog.filter(segments ++ ["content-transfer", "download", "s3cr3t"]) ==
             segments ++ ["content-transfer", "download", "[FILTERED]"]
  end

  test "a root marker comes first, then the earliest marker with a token after it" do
    assert RequestLog.filter(["__p__", "reset-password", "x"]) == ["__p__", "[FILTERED]", "x"]

    assert RequestLog.filter(["reset-password", "assistant", "shared", "x"]) == [
             "reset-password",
             "[FILTERED]",
             "shared",
             "x"
           ]

    assert RequestLog.filter(["content-transfer", "content-transfer", "download", "x"]) ==
             ["content-transfer", "content-transfer", "download", "[FILTERED]"]
  end

  test "a malformed encoding is matched as it is" do
    assert OwnLog.capture(fn -> assert RequestLog.level(conn("/admin/%zz/x"), :error) == :error end) == ""
  end

  test "the end of such a request logs nothing" do
    conn = conn("/__p__/s3cr3t") |> Plug.Conn.send_resp(200, "")
    assert OwnLog.capture(fn -> assert RequestLog.level(conn, :error) == false end) == ""
  end

  test "other paths keep the level, and log nothing here" do
    for path <- ["/", "/admin/reset-password", "/__p__", "/admin/users/1", "/projects/reset-password-tips"] do
      assert OwnLog.capture(fn -> assert RequestLog.level(conn(path), :error) == :error end) == ""
    end

    assert RequestLog.level(conn("/about"), :debug) == :debug
  end
end

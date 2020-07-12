defmodule Brando.Plug.LivePreviewTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Plug.Test

  alias Brando.Plug.LivePreview

  setup do
    opts =
      Plug.Parsers.init(
        parsers: [:urlencoded, {:multipart, length: 100_000_000}, :json],
        pass: ["*/*"],
        json_decoder: Phoenix.json_library()
      )

    Cachex.del!(:cache, "__live_preview__LIVEPREVIEWKEY")

    {:ok, %{opts: opts}}
  end

  test "live preview plug pass through", %{opts: opts} do
    conn =
      :get
      |> conn("/pass")
      |> put_req_header("content-type", "application/json")
      |> Plug.Parsers.call(opts)
      |> LivePreview.call(LivePreview.init([]))

    assert conn.status == nil
  end

  test "live preview halts on missing cache", %{opts: opts} do
    conn =
      :get
      |> conn("__livepreview?key=LIVEPREVIEWKEY")
      |> put_req_header("content-type", "application/json")
      |> Plug.Parsers.call(opts)
      |> LivePreview.call([])

    assert conn.halted == true
    assert conn.resp_body == "LIVE PREVIEW FAILED. NO DATA SET FOR KEY LIVEPREVIEWKEY"
  end

  test "live preview fails on weird data", %{opts: opts} do
    Brando.LivePreview.store_cache(
      "LIVEPREVIEWKEY",
      [nil, []]
    )

    conn =
      :get
      |> conn("__livepreview?key=LIVEPREVIEWKEY")
      |> put_req_header("content-type", "application/json")
      |> Plug.Parsers.call(opts)
      |> LivePreview.call([])

    assert conn.halted == true

    assert conn.resp_body ==
             "LIVE PREVIEW FAILED\n\n%FunctionClauseError{\n  args: nil,\n  arity: 3,\n  clauses: nil,\n  function: :split,\n  kind: nil,\n  module: String\n}"
  end

  test "live preview succeeds", %{opts: opts} do
    Brando.LivePreview.store_cache(
      "LIVEPREVIEWKEY",
      "<html><head></head><body><main><h1>test</h1></main></body></html>"
    )

    conn =
      :get
      |> conn("__livepreview?key=LIVEPREVIEWKEY")
      |> put_req_header("content-type", "application/json")
      |> Plug.Parsers.call(opts)
      |> LivePreview.call([])

    assert conn.halted == true
    assert conn.resp_body =~ "</main><!-- BRANDO LIVE PREVIEW -->"
  end
end

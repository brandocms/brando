defmodule Brando.Plug.IdentityTest do
  use ExUnit.Case
  use Plug.Test

  alias Brando.Plug.Identity

  setup do
    opts =
      Plug.Parsers.init(
        parsers: [:urlencoded, {:multipart, length: 100_000_000}, :json],
        pass: ["*/*"],
        json_decoder: Phoenix.json_library()
      )

    {:ok, %{opts: opts}}
  end

  test "sentry user context pass", %{opts: opts} do
    conn =
      :get
      |> conn("/pass")
      |> Plug.Parsers.call(opts)
      |> Identity.call(Identity.init([]))

    refute conn.assigns.identity == nil
  end
end

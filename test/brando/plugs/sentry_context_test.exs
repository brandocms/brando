defmodule Brando.Plug.SentryUserContextTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Plug.Test

  alias Brando.Factory
  alias Brando.Plug.SentryUserContext

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
      |> SentryUserContext.call(SentryUserContext.init([]))

    assert conn.status == nil

    conn =
      :get
      |> conn("/pass")
      |> put_private(:current_user, nil)
      |> Plug.Parsers.call(opts)
      |> SentryUserContext.call(SentryUserContext.init([]))

    assert conn.status == nil
  end

  test "sentry user context set", %{opts: opts} do
    u1 = Factory.insert(:random_user)

    conn =
      :get
      |> conn("/pass")
      |> put_private(:current_user, u1)
      |> Plug.Parsers.call(opts)
      |> SentryUserContext.call(SentryUserContext.init([]))

    assert conn.status == nil

    context = Sentry.Context.get_all()

    assert context.user.email == u1.email
    assert context.user.id == u1.id
  end
end

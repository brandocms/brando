defmodule BrandoAdmin.ChromeSocketTokensTest do
  @moduledoc """
  The admin socket authenticates with tokens rendered into the page at load,
  verified with a 24h max_age. A tab open longer could not reconnect after a
  server restart and dropped out of presence until reloaded. The Chrome
  LiveView, which authenticates with the session and remounts after a restart,
  hands the page fresh ones.
  """

  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Phoenix.LiveViewTest

  test "pushes socket tokens for the signed-in user on mount" do
    user = Brando.Factory.insert(:random_user)
    session_token = Brando.Users.generate_user_session_token(user)

    {:ok, view, _} = live_isolated(build_conn(), BrandoAdmin.Chrome, session: %{"user_token" => session_token})

    assert_push_event(view, "brando:socket_tokens", %{user_token: token, realtime_scope: scope_token})
    assert {:ok, user_id} = Brando.Users.verify_token(token)
    assert user_id == user.id
    assert {:ok, _scope} = Brando.Authorization.Realtime.verify_scope(scope_token, user.id)
  end
end

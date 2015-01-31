Code.require_file("router_helper.exs", Path.join([__DIR__, "..", ".."]))

defmodule Brando.Users.ControllerTest do
  use ExUnit.Case, async: true
  use Plug.Test
  use RouterHelper

  test "index redirects to /login" do
    conn = call_with_session(RouterHelper.TestRouter, :get, "/admin/brukere")
    assert conn.status == 302
    assert elem(List.keyfind(conn.resp_headers, "Location", 0), 1) == "/login"
  end

  test "index with logged in user" do
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/brukere")
    assert conn.status == 200
  end
end
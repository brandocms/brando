Code.require_file("router_helper.exs", Path.join([__DIR__, "..", ".."]))

defmodule Brando.Auth.ControllerTest do
  use ExUnit.Case
  use Brando.Integration.TestCase
  use Plug.Test
  use RouterHelper
  alias Brando.User

  @params %{"avatar" => nil, "role" => ["2", "4"],
            "email" => "admin@gmail.com", "full_name" => "Admin Admin",
            "password" => "finimeze", "status" => "1",
            "submit" => "Submit", "username" => "zabuzasixu"}

  @login %{"email" => "admin@gmail.com", "password" => "finimeze"}
  @bad_login %{"email" => "bad@gmail.com", "password" => "finimeze"}

  test "login get" do
    conn = call_with_session(RouterHelper.TestRouter, :get, "/login")
    assert conn.status == 200
    assert conn.path_info == ["login"]
    assert conn.resp_body =~ "<form"
  end

  test "login post ok" do
    assert {:ok, _user} = User.create(@params)
    conn = call_with_session(RouterHelper.TestRouter, :post, "/login", %{"user" => @login})
    assert conn.status == 302
    assert get_resp_header(conn, "Location") == ["/admin"]
    %{phoenix_flash: flash} = conn.private
    assert flash == %{"notice" => "Innloggingen var vellykket"}
  end

  test "login post failed" do
    assert {:ok, _user} = User.create(@params)
    conn = call_with_session(RouterHelper.TestRouter, :post, "/login", %{"user" => @bad_login})
    assert conn.status == 302
    assert get_resp_header(conn, "Location") == ["/login"]
    %{phoenix_flash: flash} = conn.private
    assert flash == %{"error" => "Innloggingen feilet"}
  end

  test "logout" do
    conn = call_with_session(RouterHelper.TestRouter, :get, "/logout")
    assert conn.status == 200
    assert conn.path_info == ["logout"]
    assert conn.resp_body =~ "Du er logget ut av administrasjonsområdet"
  end
end
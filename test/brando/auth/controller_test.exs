defmodule Brando.Auth.ControllerTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  use Plug.Test
  use RouterHelper

  @login %{"email" => "james@thestooges.com", "password" => "hunter2hunter2"}
  @bad_login %{"email" => "bad@gmail.com", "password" => "finimeze"}

  test "login get" do
    conn =
      call(:get, "/login")
      |> with_session
      |> send_request
    assert html_response(conn, 200) =~ "Passord"
  end

  test "login post ok" do
    Forge.saved_user_w_hashed_pass(TestRepo)
    conn =
      call(:post, "/login", %{"user" => @login})
      |> with_session
      |> send_request
    assert redirected_to(conn, 302) =~ "/admin"
    assert get_flash(conn, :notice) == "Innloggingen var vellykket"

  end

  test "login post failed" do
    Forge.saved_user_w_hashed_pass(TestRepo)
    conn =
      call(:post, "/login", %{"user" => @bad_login})
      |> with_session
      |> send_request
    assert redirected_to(conn, 302) =~ "/login"
    assert get_flash(conn, :error) == "Innloggingen feilet"
  end

  test "logout" do
    user = Forge.saved_user_w_hashed_pass(TestRepo)
    conn =
      call(:get, "/logout")
      |> with_user(user)
      |> send_request
    assert html_response(conn, 200) =~ "Du er logget ut av administrasjonsområdet"
  end
end
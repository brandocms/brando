defmodule Brando.Auth.ControllerTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  use Plug.Test
  use RouterHelper

  alias Brando.Factory

  @login %{
    "email" => "james@thestooges.com",
    "password" => "hunter2hunter2"
  }

  @bad_login %{
    "email" => "bad@gmail.com",
    "password" => "finimeze"
  }

  test "login get" do
    conn =
      :get
      |> call("/login")
      |> with_session
      |> send_request
    assert html_response(conn, 200) =~ "Password"
  end

  test "login post ok" do
    Factory.create(:user)

    conn =
      :post
      |> call("/login", %{"user" => @login})
      |> with_session
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin"
  end

  test "login post failed" do
    Factory.create(:user)

    conn =
      :post
      |> call("/login", %{"user" => @bad_login})
      |> with_session
      |> send_request

    assert redirected_to(conn, 302) =~ "/login"
    assert get_flash(conn, :error) == "Authorization failed"
  end

  test "logout" do
    user = Factory.create(:user)

    conn =
      :get
      |> call("/logout")
      |> with_user(user)
      |> send_request

    assert html_response(conn, 200) =~ "You have been logged out of the admin area"
  end
end

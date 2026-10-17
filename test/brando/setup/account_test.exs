defmodule Brando.Setup.AccountTest do
  use Brando.LiveCase

  alias Brando.Setup.Account

  describe "create_superuser/1" do
    test "the account logs in with the password setup was given, with no change asked for" do
      user = Account.create_superuser(%{email: "setup@example.com", name: "Setup", password: "chosen at setup"})

      assert user.role == :superuser
      assert %{reset_password_on_first_login: false} = Repo.get!(Brando.Users.User, user.id).config

      conn =
        post(Phoenix.ConnTest.build_conn(), "/admin/login", %{
          "user" => %{"email" => "setup@example.com", "password" => "chosen at setup"}
        })

      assert redirected_to(conn) == "/admin"
    end
  end
end

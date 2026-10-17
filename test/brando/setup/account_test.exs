defmodule Brando.Setup.AccountTest do
  use Brando.LiveCase

  alias Brando.Setup.Account
  alias Brando.Users.UserConfig

  defp log_in(email, password) do
    post(Phoenix.ConnTest.build_conn(), "/admin/login", %{"user" => %{"email" => email, "password" => password}})
  end

  describe "create_superuser/1" do
    test "the account logs in with the password setup was given, with no change asked for" do
      user = Account.create_superuser(%{email: "setup@example.com", name: "Setup", password: "chosen at setup"})

      assert user.role == :superuser
      assert %{reset_password_on_first_login: false} = Repo.get!(Brando.Users.User, user.id).config
      assert redirected_to(log_in("setup@example.com", "chosen at setup")) == "/admin"

      # What a database's `{}` config default loads as: the change is asked for
      other = Factory.insert(:random_user, config: %UserConfig{})
      assert redirected_to(log_in(other.email, "admin")) == "/admin/users/password"
    end
  end
end

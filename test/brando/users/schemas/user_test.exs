defmodule Brando.Integration.UserTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase

  alias Brando.Factory
  alias Brando.Users

  test "create/1 and update/1" do
    user = Factory.insert(:random_user)

    assert {:ok, updated_user} =
             Users.update_user(user.id, %{"full_name" => "Elvis Presley"}, :system)

    assert updated_user.full_name == "Elvis Presley"

    old_pass = updated_user.password

    assert {:ok, updated_password_user} =
             Users.update_user(updated_user.id, %{"password" => "newpass"}, :system)

    refute old_pass == updated_password_user.password
    refute updated_password_user.password == "newpass"
  end
end

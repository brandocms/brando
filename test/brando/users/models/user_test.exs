defmodule Brando.Integration.UserTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase

  alias Brando.User
  alias Brando.Users
  alias Brando.Factory

  test "create/1 and update/1" do
    user = Factory.insert(:user)

    assert {:ok, updated_user} = Users.update_user(user.id, %{"full_name" => "Elvis Presley"})
    assert updated_user.full_name == "Elvis Presley"

    old_pass = updated_user.password
    assert {:ok, updated_password_user}
           = Users.update_user(updated_user.id, %{"password" => "newpass"})
    refute old_pass == updated_password_user.password
    refute updated_password_user.password == "newpass"
  end

  test "auth?/2" do
    user = Factory.insert(:user)

    assert User.auth?(user, "hunter2hunter2")
    refute User.auth?(user, "finimeze123")
  end

  test "role?/1" do
    user = Factory.insert(:user)

    assert User.role?(user, :superuser)
    refute User.role?(user, :admin)
    refute User.role?(user, :staff)
  end
end

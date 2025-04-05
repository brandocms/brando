defmodule BrandoIntegration.UsersTest do
  use ExUnit.Case
  use Brando.ConnCase
  use BrandoIntegration.TestCase

  alias Brando.Factory
  alias Brando.Users

  test "set_last_login/1" do
    user = Factory.insert(:user)
    {:ok, new_user} = Users.set_last_login(user)
    refute user.last_login == new_user.last_login
  end
end

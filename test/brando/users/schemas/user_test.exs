defmodule BrandoIntegration.UserTest do
  use ExUnit.Case
  use Brando.ConnCase
  use BrandoIntegration.TestCase

  alias Brando.Factory
  alias Brando.Users
  alias Brando.Users.UserConfig

  test "embedded config uses the configured default content language" do
    assert %UserConfig{content_language: default_language} = %UserConfig{}
    assert default_language == Brando.RuntimeConfig.get(:default_language)
  end

  test "create/1 and update/1" do
    user = Factory.insert(:random_user)

    assert {:ok, updated_user} = Users.update_user(user.id, %{"name" => "Elvis Presley"}, :system)

    assert updated_user.name == "Elvis Presley"

    old_pass = updated_user.password

    assert {:ok, updated_password_user} =
             Users.update_user(updated_user.id, %{"password" => "newpass"}, :system)

    refute old_pass == updated_password_user.password
    refute updated_password_user.password == "newpass"
    assert Bcrypt.verify_pass("newpass", updated_password_user.password)
  end

  test "a password created through the context is stored hashed" do
    admin = Factory.insert(:random_user)

    {:ok, user} =
      Users.create_user(
        %{
          name: "Alex Editor",
          email: "alex@example.com",
          password: "initial-secret",
          password_confirmation: "initial-secret",
          language: "en",
          role: :editor
        },
        admin
      )

    {:ok, stored} = Users.get_user(user.id)
    refute stored.password == "initial-secret"
    assert Bcrypt.verify_pass("initial-secret", stored.password)
  end

  test "a validated changeset that is not written keeps the plain text for validation" do
    changeset = Brando.Users.User.changeset(%Brando.Users.User{}, %{"password" => "short"}, :system)

    assert {"should be at least %{count} character(s)", _} = changeset.errors[:password]
  end

  test "a blank password keeps the current one" do
    user = Factory.insert(:random_user)

    assert {:ok, updated_user} =
             Users.update_user(user.id, %{"name" => "Elvis Presley", "password" => ""}, :system)

    assert updated_user.name == "Elvis Presley"
    assert updated_user.password == user.password
  end

  test "a new user still needs a password" do
    changeset = Brando.Users.User.changeset(%Brando.Users.User{}, %{"password" => ""}, :system)

    assert {"can't be blank", _} = changeset.errors[:password]
  end
end

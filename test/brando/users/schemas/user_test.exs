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

    # A saved user's password changes only through the password functions,
    # which end the user's sessions and connected tools.
    assert {:error, changeset} = Users.update_user(updated_user.id, %{"password" => "newpass1"}, :system)
    assert changeset.errors[:password]
    assert Brando.Repo.get!(Brando.Users.User, user.id).password == old_pass
  end

  test "changing the password ends the user's sessions and connected tools" do
    user = Factory.insert(:random_user, config: %UserConfig{})
    Users.generate_user_session_token(user)

    grant =
      Brando.Repo.insert!(%Brando.MCP.Grant{
        user_id: user.id,
        resource: "http://localhost/mcp",
        client_id: "https://client.example/c.json",
        client_name: "Client",
        redirect_uri: "https://client.example/cb",
        scope: "content"
      })

    assert {:ok, _} =
             Users.reset_user_password(user, %{password: "a new password 1", password_confirmation: "a new password 1"})

    assert Brando.Repo.get!(Brando.MCP.Grant, grant.id).revoked_reason == "password_changed"
    assert Brando.Repo.aggregate(from(t in Brando.Users.UserToken, where: t.user_id == ^user.id), :count) == 0
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

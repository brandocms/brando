defmodule Brando.AuthorizationTest do
  use ExUnit.Case, async: true

  defmodule TestAuth do
    use Brando.Authorization

    alias Brando.Users.User
    alias Brando.Pages.Page

    types [
      {"User", Brando.Users.User},
      {"Page", Brando.Pages.Page}
    ]

    rules :superuser do
      can :manage, :all
    end

    rules :banned do
      cannot :manage, :all
    end

    rules :admin do
      can :manage, :all
      can :read, %Page{}
      cannot :manage, %User{}, when: %{role: :superuser}
      cannot :read, "MenuItem", when: %{to: %{name: "templates"}}
    end

    rules :user do
      can :manage, :all
      cannot :manage, %User{}
      cannot :manage, %Page{}
    end

    rules :admin_read do
      can :manage, :all
      cannot :read, %User{}, when: %{role: :superuser}
    end
  end

  alias Brando.AuthorizationTest.TestAuth

  test "superuser can do anything" do
    user = %Brando.Users.User{role: :superuser}
    page = %Brando.Pages.Page{status: :published}

    assert TestAuth.Can.can?(user, :manage, page) === {:ok, :authorized}
    assert TestAuth.Can.can?(user, :create, page) === {:ok, :authorized}
    assert TestAuth.Can.can?(user, :read, page) === {:ok, :authorized}
    assert TestAuth.Can.can?(user, :update, page) === {:ok, :authorized}
    assert TestAuth.Can.can?(user, :delete, page) === {:ok, :authorized}
  end

  test "banned can't do anything" do
    user = %Brando.Users.User{role: :banned}
    page = %Brando.Pages.Page{status: :published}

    assert TestAuth.Can.can?(user, :manage, page) === {:error, :unauthorized}
    assert TestAuth.Can.can?(user, :create, page) === {:error, :unauthorized}
    assert TestAuth.Can.can?(user, :read, page) === {:error, :unauthorized}
    assert TestAuth.Can.can?(user, :update, page) === {:error, :unauthorized}
    assert TestAuth.Can.can?(user, :delete, page) === {:error, :unauthorized}
  end

  test "admin can and cannot" do
    user = %Brando.Users.User{role: :admin}
    page = %Brando.Pages.Page{status: :published}

    regular_user = %Brando.Users.User{role: :user}
    superuser = %Brando.Users.User{role: :superuser}

    assert TestAuth.Can.can?(user, :manage, page) === {:ok, :authorized}
    assert TestAuth.Can.can?(user, :create, page) === {:ok, :authorized}
    assert TestAuth.Can.can?(user, :read, page) === {:ok, :authorized}
    assert TestAuth.Can.can?(user, :update, page) === {:ok, :authorized}
    assert TestAuth.Can.can?(user, :delete, page) === {:ok, :authorized}

    assert TestAuth.Can.can?(user, :manage, regular_user) === {:ok, :authorized}
    assert TestAuth.Can.can?(user, :manage, superuser) === {:error, :unauthorized}

    assert TestAuth.Can.can?(user, :read, superuser) === {:error, :unauthorized}

    assert_raise ArgumentError, fn ->
      TestAuth.Can.can?(user, :read, "MenuItem")
    end
  end

  test "admin_read can and cannot" do
    user = %Brando.Users.User{role: :admin_read}

    regular_user = %Brando.Users.User{role: :user}
    superuser = %Brando.Users.User{role: :superuser}

    assert TestAuth.Can.can?(user, :read, regular_user) === {:ok, :authorized}
    assert TestAuth.Can.can?(user, :read, superuser) === {:error, :unauthorized}
    assert TestAuth.Can.can?(user, :create, regular_user) === {:ok, :authorized}
    assert TestAuth.Can.can?(user, :create, superuser) === {:ok, :authorized}
  end

  test "user cannot" do
    user = %Brando.Users.User{role: :user}
    page = %Brando.Pages.Page{status: :published}

    regular_user = %Brando.Users.User{role: :user}
    superuser = %Brando.Users.User{role: :superuser}

    assert TestAuth.Can.can?(user, :read, superuser) === {:error, :unauthorized}
    assert TestAuth.Can.can?(user, :read, regular_user) === {:error, :unauthorized}
    assert TestAuth.Can.can?(user, :read, page) === {:error, :unauthorized}
  end

  test "get rules for frontend" do
    assert TestAuth.get_rules_for(:admin) ===
             [
               %Brando.Authorization.Rule{
                 action: :manage,
                 conditions: nil,
                 inverted: false,
                 subject: "all"
               },
               %Brando.Authorization.Rule{
                 action: :read,
                 conditions: nil,
                 inverted: false,
                 subject: "Page"
               },
               %Brando.Authorization.Rule{
                 action: :manage,
                 conditions: %{role: :superuser},
                 inverted: true,
                 subject: "User"
               },
               %Brando.Authorization.Rule{
                 action: :read,
                 conditions: %{to: %{name: "templates"}},
                 inverted: true,
                 subject: "MenuItem"
               }
             ]
  end

  test "generating rules from DSL" do
    assert TestAuth.__rules__(:superuser) == [
             %Brando.Authorization.Rule{
               action: :manage,
               conditions: nil,
               inverted: false,
               subject: "all"
             }
           ]

    assert TestAuth.__rules__(:admin) == [
             %Brando.Authorization.Rule{
               action: :manage,
               conditions: nil,
               inverted: false,
               subject: "all"
             },
             %Brando.Authorization.Rule{
               action: :read,
               conditions: nil,
               inverted: false,
               subject: Brando.Pages.Page
             },
             %Brando.Authorization.Rule{
               action: :manage,
               conditions: %{role: :superuser},
               inverted: true,
               subject: Brando.Users.User
             },
             %Brando.Authorization.Rule{
               action: :read,
               conditions: %{to: %{name: "templates"}},
               inverted: true,
               subject: "MenuItem"
             }
           ]

    assert TestAuth.__rules__(:user) == [
             %Brando.Authorization.Rule{
               action: :manage,
               conditions: nil,
               inverted: false,
               subject: "all"
             },
             %Brando.Authorization.Rule{
               action: :manage,
               conditions: nil,
               inverted: true,
               subject: Brando.Users.User
             },
             %Brando.Authorization.Rule{
               action: :manage,
               conditions: nil,
               inverted: true,
               subject: Brando.Pages.Page
             }
           ]
  end
end

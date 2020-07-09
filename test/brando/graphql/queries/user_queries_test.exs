defmodule Brando.GraphQL.Queries.UserQueriesTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase

  alias Brando.Factory

  setup do
    u1 = Factory.insert(:random_user)
    opts = [context: %{current_user: u1}]

    {:ok, %{user: u1, opts: opts}}
  end

  @user_query """
  query {
    users {
      id
      fullName
    }
  }
  """

  test "users", %{opts: opts, user: user} do
    assert Absinthe.run(
             @user_query,
             Brando.Integration.TestSchema,
             opts
           ) ==
             {:ok,
              %{
                data: %{
                  "users" => [%{"fullName" => "James Williamson", "id" => to_string(user.id)}]
                }
              }}
  end

  @user_id_query """
  query user($userId: ID) {
    user(userId: $userId) {
      id
      fullName
    }
  }
  """
  test "user(id)", %{opts: opts, user: user} do
    assert Absinthe.run(
             @user_id_query,
             Brando.Integration.TestSchema,
             opts ++ [variables: %{"userId" => user.id}]
           ) ==
             {:ok,
              %{
                data: %{
                  "user" => %{"fullName" => "James Williamson", "id" => to_string(user.id)}
                }
              }}
  end

  @me_query """
  query me {
    me {
      id
      fullName
    }
  }
  """
  test "me", %{opts: opts, user: user} do
    assert Absinthe.run(
             @me_query,
             Brando.Integration.TestSchema,
             opts
           ) ==
             {:ok,
              %{
                data: %{
                  "me" => %{"fullName" => "James Williamson", "id" => to_string(user.id)}
                }
              }}
  end
end

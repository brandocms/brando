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
      name
    }
  }
  """

  test "users", %{opts: opts, user: user} do
    assert Absinthe.run(
             @user_query,
             BrandoIntegration.TestSchema,
             opts
           ) ==
             {:ok,
              %{
                data: %{
                  "users" => [%{"name" => "James Williamson", "id" => to_string(user.id)}]
                }
              }}
  end

  @user_id_query """
  query user($userId: ID) {
    user(userId: $userId) {
      id
      name
    }
  }
  """
  test "user(id)", %{opts: opts, user: user} do
    assert Absinthe.run(
             @user_id_query,
             BrandoIntegration.TestSchema,
             opts ++ [variables: %{"userId" => user.id}]
           ) ==
             {:ok,
              %{
                data: %{
                  "user" => %{"name" => "James Williamson", "id" => to_string(user.id)}
                }
              }}

    assert Absinthe.run(
             @user_id_query,
             BrandoIntegration.TestSchema,
             opts ++ [variables: %{"userId" => 9_999_999_999}]
           ) ==
             {:ok,
              %{
                data: %{"user" => nil},
                errors: [
                  %{
                    locations: [%{column: 3, line: 2}],
                    message: "User id 9999999999 not found",
                    path: ["user"]
                  }
                ]
              }}
  end

  @me_query """
  query me {
    me {
      id
      name

      avatar {
        focal
        thumb: url(size: "thumb")
        medium: url(size: "medium")
        xlarge: url(size: "xlarge")
      }
    }
  }
  """
  test "me", %{opts: opts, user: user} do
    assert Absinthe.run(
             @me_query,
             BrandoIntegration.TestSchema,
             opts
           ) ==
             {
               :ok,
               %{
                 data: %{
                   "me" => %{
                     "name" => "James Williamson",
                     "id" => to_string(user.id),
                     "avatar" => %{
                       "focal" => %Brando.Images.Focal{x: 50, y: 50},
                       "medium" => "/media/images/avatars/medium/27i97a.jpeg",
                       "thumb" => "/media/images/avatars/thumb/27i97a.jpeg",
                       "xlarge" => ""
                     }
                   }
                 }
               }
             }
  end
end

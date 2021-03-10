defmodule Brando.Users.UserResolver do
  @moduledoc """
  Resolver for Users
  """
  use Brando.Web, :resolver

  use Brando.GraphQL.Resolver,
    context: Brando.Users,
    schema: Brando.Users.User

  alias Brando.Users

  @doc """
  Get current user
  """
  def me(_, %{context: %{current_user: current_user}}) do
    Users.get_user(%{matches: %{id: current_user.id}})
  end
end

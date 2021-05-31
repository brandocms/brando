defmodule Brando.Users.UserResolver do
  @moduledoc """
  Resolver for Users
  """
  use BrandoAdmin, :resolver

  use BrandoGraphQL.Resolver,
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

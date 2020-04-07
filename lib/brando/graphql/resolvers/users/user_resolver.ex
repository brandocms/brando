defmodule Brando.Users.UserResolver do
  @moduledoc """
  Resolver for Users
  """
  use Brando.Web, :resolver
  alias Brando.Users
  alias Brando.Users.User

  import Ecto.Query

  @doc """
  Get current user
  """
  def me(_, %{context: %{current_user: current_user}}) do
    require Logger
    Logger.debug("-- $resolver: :users(me)")

    me =
      Brando.repo().one(
        from user in User,
          where: user.id == ^current_user.id
      )

    case me do
      nil -> {:error, "User id #{current_user.id} not found"}
      user -> {:ok, user}
    end
  end

  @doc """
  Get current user
  """
  def find(%{user_id: user_id}, %{context: %{current_user: _current_user}}) do
    require Logger
    Logger.debug("-- $resolver: :users(find)")

    user =
      Brando.repo().one(
        from user in User,
          where: user.id == ^user_id
      )

    case user do
      nil -> {:error, "User id #{user_id} not found"}
      user -> {:ok, user}
    end
  end

  @doc """
  Get all users
  """
  def all(_, %{context: %{current_user: _current_user}}) do
    users =
      Brando.repo().all(
        from user in User,
          order_by: [asc: user.full_name]
      )

    {:ok, users}
  end

  @doc """
  create user
  """
  def create(%{user_params: user_params}, %{context: %{current_user: current_user}}) do
    user_params
    |> Users.create_user(current_user)
    |> response
  end

  @doc """
  update user
  """
  def update(%{user_id: user_id, user_params: user_params}, %{
        context: %{current_user: current_user}
      }) do
    user_id
    |> Users.update_user(user_params, current_user)
    |> response
  end
end

defmodule Brando.Users do
  @moduledoc """
  Context for Users.

  Interfaces with database
  """
  alias Brando.Utils
  alias Brando.User

  def get_user_by(args) do
    Brando.repo.get_by(User, args)
  end

  def get_user_by!(args) do
    Brando.repo.get_by!(User, args)
  end

  def get_users() do
    User
    |> User.order_by_id()
    |> Brando.repo.all()
  end

  def create_user(params) do
    params
    |> User.create()
    |> Brando.repo.insert
  end

  def update_user(id, params) do
    get_user_by!(id: id)
    |> User.update(params)
    |> Brando.repo.update
  end

  def delete_user(user) do
    Brando.repo.delete!(user)
  end

  @doc """
  Bumps `user`'s `last_login` to current time.
  """
  @spec set_last_login(User) :: User
  def set_last_login(user) do
    {:ok, user} =
      Utils.Schema.update_field(user, [last_login: NaiveDateTime.from_erl!(:calendar.local_time)])
    user
  end
end

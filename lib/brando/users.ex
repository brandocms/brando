defmodule Brando.Users do
  @moduledoc """
  Context for Users.

  Interfaces with database
  """
  alias Brando.User
  alias Brando.Utils
  import Ecto.Changeset

  @doc """
  Get user by id
  """
  def get_user(id) do
    case Brando.repo().get(User, id) do
      nil -> {:error, {:user, :not_found}}
      user -> {:ok, user}
    end
  end

  @doc """
  Get user by `args` kw list
  """
  def get_user_by(args), do: Brando.repo().get_by(User, args)

  @doc """
  Get user by `args` kw list
  """
  def get_user_by!(args) do
    Brando.repo().get_by!(User, args)
  end

  @doc """
  List users
  """
  def get_users() do
    User
    |> User.order_by_id()
    |> Brando.repo().all()
  end

  @doc """
  Create user
  """
  def create_user(params) do
    User.changeset(%User{}, :create, params)
    |> maybe_update_password
    |> Brando.repo().insert
  end

  @doc """
  Update user
  """
  def update_user(id, params) do
    with {:ok, user} <- get_user(id) do
      user
      |> User.changeset(:update, params)
      |> maybe_update_password
      |> Brando.repo().update
    else
      _ -> {:error, {:user, :not_found}}
    end
  end

  @doc """
  Delete user
  """
  def delete_user(user), do: Brando.repo().delete!(user)

  @doc """
  Bumps `user`'s `last_login` to current time.
  """
  @spec set_last_login(User.t()) :: User.t()
  def set_last_login(user) do
    current_time = NaiveDateTime.from_erl!(:calendar.local_time())
    {:ok, user} = Utils.Schema.update_field(user, last_login: current_time)

    user
  end

  @doc """
  Set user status
  """
  def set_active(user_id, status) do
    {:ok, user} = get_user(user_id)

    user
    |> Ecto.Changeset.change(%{active: status})
    |> Brando.repo().update
  end

  defp maybe_update_password(%{changes: %{password: password}} = cs),
    do: put_change(cs, :password, Bcrypt.hash_pwd_salt(password))

  defp maybe_update_password(cs), do: cs
end

defmodule Brando.Users do
  @moduledoc """
  Context for Users.

  Interfaces with database
  """
  alias Brando.Utils
  alias Brando.User
  import Ecto.Changeset

  def get_user(id) do
    case Brando.repo.get(User, id) do
      nil -> {:error, {:user, :not_found}}
      user -> {:ok, user}
    end
  end

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
    User.changeset(%User{}, :create, params)
    |> maybe_update_password
    |> Brando.repo.insert
  end

  def update_user(id, params) do
    with {:ok, user} <- get_user(id) do
      user
      |> User.changeset(:update, params)
      |> maybe_update_password
      |> Brando.repo.update
    else
      _ -> {:error, {:user, :not_found}}
    end
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

  defp maybe_update_password(%{changes: %{password: password}} = cs) do
    put_change(cs, :password, Comeonin.Bcrypt.hashpwsalt(password))
  end

  defp maybe_update_password(cs), do: cs
end

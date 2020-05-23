defmodule Brando.Users do
  @moduledoc """
  Context for Users.
  """
  use Brando.Web, :context
  alias Brando.Users.User
  alias Brando.Utils
  import Ecto.Changeset
  import Ecto.Query

  @type user :: User.t()

  @doc """
  Dataloader initializer
  """
  def data(_) do
    Dataloader.Ecto.new(
      Brando.repo(),
      query: &query/2
    )
  end

  @doc """
  Dataloader queries
  """
  def query(queryable, _), do: queryable

  @doc """
  Get user by id
  """
  def get_user(id) do
    query = from t in User, where: t.id == ^id and is_nil(t.deleted_at)

    case Brando.repo().one(query) do
      nil -> {:error, {:user, :not_found}}
      user -> {:ok, user}
    end
  end

  @doc """
  Get non deleted user by email
  """
  def get_user_by_email(email) do
    query = from t in User, where: t.email == ^email and is_nil(t.deleted_at) and t.active == true

    case Brando.repo().one(query) do
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
  Orders by ID
  """
  def order_by_id(query), do: from(m in query, order_by: m.id)

  @doc """
  List users
  """
  def get_users do
    User
    |> order_by_id()
    |> exclude_deleted()
    |> Brando.repo().all()
  end

  @doc """
  Create user
  """
  def create_user(params, current_user) do
    User.changeset(%User{}, params, current_user)
    |> maybe_update_password()
    |> Brando.repo().insert
  end

  @doc """
  Update user
  """
  def update_user(id, params, current_user) do
    case get_user(id) do
      {:ok, user} ->
        user
        |> User.changeset(params, current_user)
        |> maybe_update_password
        |> Brando.repo().update

      _ ->
        {:error, {:user, :not_found}}
    end
  end

  @doc """
  Delete user
  """
  def delete_user(user), do: Brando.repo().soft_delete!(user)

  @doc """
  Bumps `user`'s `last_login` to current time.
  """
  @spec set_last_login(user) :: user
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

  @doc """
  Checks if `user` has access to admin area.
  """
  @spec can_login?(user) :: boolean
  def can_login?(user) do
    {:ok, role} = Brando.Type.Role.dump(user.role)
    (role > 0 && true) || false
  end

  defp maybe_update_password(%{changes: %{password: password}} = cs),
    do: put_change(cs, :password, Bcrypt.hash_pwd_salt(password))

  defp maybe_update_password(cs), do: cs
end

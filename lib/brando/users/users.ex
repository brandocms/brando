defmodule Brando.Users do
  @moduledoc """
  Context for Users.
  """
  use BrandoAdmin, :context
  use Brando.Query
  alias Brando.Users.User
  alias Brando.Users.UserToken
  alias Brando.Utils
  import Ecto.Query

  @type user :: User.t()

  query :list, User do
    fn q -> from t in q, where: is_nil(t.deleted_at) end
  end

  filters User do
    fn
      {:active, active}, q -> from t in q, where: t.active == ^active
      {:name, name}, q -> from t in q, where: ilike(t.name, ^"%#{name}%")
      {:email, email}, q -> from t in q, where: ilike(t.email, ^"%#{email}%")
    end
  end

  query :single, User do
    fn q -> from t in q, where: is_nil(t.deleted_at) end
  end

  matches User do
    fn
      {:id, id}, q -> from t in q, where: t.id == ^id
      {:email, email}, q -> from t in q, where: t.email == ^email
      {:password, password}, q -> from t in q, where: t.password == ^password
      {:active, active}, q -> from t in q, where: t.active == ^active
      {field, value}, q -> from t in q, where: field(t, ^field) == ^value
    end
  end

  mutation :create, User
  mutation :update, User
  mutation :delete, User

  @doc """
  Bumps `user`'s `last_login` to current time.
  """
  @spec set_last_login(user) :: {:ok, user}
  def set_last_login(user) do
    current_time = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    Utils.Schema.update_field(user, last_login: current_time)
  end

  @doc """
  Set user status
  """
  def set_active(user_id, status, user) do
    update_user(user_id, %{active: status}, user)
  end

  @doc """
  Checks if `user` has access to admin area.
  """
  @spec can_login?(user) :: boolean
  def can_login?(user) do
    {:ok, role} = Brando.Type.Role.dump(user.role)
    (role > 0 && true) || false
  end

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Brando.repo().insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Brando.repo().one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_session_token(token) do
    Brando.repo().delete_all(UserToken.token_and_context_query(token, "session"))
    :ok
  end

  def build_token(id) do
    Phoenix.Token.sign(Brando.endpoint(), "user_token", id)
  end

  def verify_token(token) do
    Phoenix.Token.verify(Brando.endpoint(), "user_token", token, max_age: 86_400)
  end

  def reset_user_password(_user, _attrs) do
    raise "TODO"
  end
end

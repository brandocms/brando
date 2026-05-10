defmodule Brando.Users do
  @moduledoc """
  Context for Users.
  """
  use BrandoAdmin, :context
  use Brando.Query
  use Gettext, backend: Brando.Gettext

  import Ecto.Query

  alias Brando.Users.User
  alias Brando.Users.UserToken
  alias Brando.Utils

  @type user :: User.t()

  query :list, User do
    fn q -> from(t in q) end
  end

  filters User do
    fn
      {:ids, ids}, q -> from t in q, where: t.id in ^ids
      {:active, active}, q -> from t in q, where: t.active == ^active
      {:name, name}, q -> from t in q, where: ilike(t.name, ^"%#{name}%")
      {:email, email}, q -> from t in q, where: ilike(t.email, ^"%#{email}%")
    end
  end

  query :single, User do
    fn q -> from(t in q) end
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

    query
    |> Brando.repo().one()
    |> Brando.repo().preload(:avatar)
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

  @doc """
  Returns all foreign key references pointing at the `users` table.
  Queries `information_schema` so it catches everything — app blueprints,
  Brando internals, and manual FKs alike.
  """
  @spec get_user_foreign_key_references() :: [{String.t(), String.t()}]
  def get_user_foreign_key_references do
    %{rows: rows} =
      Ecto.Adapters.SQL.query!(
        Brando.repo(),
        """
        SELECT tc.table_name, kcu.column_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name
        JOIN information_schema.constraint_column_usage ccu
          ON ccu.constraint_name = tc.constraint_name
        WHERE tc.constraint_type = 'FOREIGN KEY'
          AND ccu.table_name = 'users'
        """,
        []
      )

    Enum.map(rows, fn [table, column] -> {table, column} end)
  end

  @doc """
  Returns a content summary for `user_id` — a list of tables and how many
  rows reference this user, filtering out tables with zero rows.
  """
  @spec get_user_content_summary(integer()) :: [map()]
  def get_user_content_summary(user_id) do
    get_user_foreign_key_references()
    |> Enum.reject(fn {table, _col} -> table == "users_tokens" end)
    |> Enum.map(fn {table, column} ->
      %{rows: [[count]]} =
        Ecto.Adapters.SQL.query!(
          Brando.repo(),
          "SELECT count(*) FROM #{table} WHERE #{column} = $1",
          [user_id]
        )

      %{table: table, column: column, count: count}
    end)
    |> Enum.reject(&(&1.count == 0))
  end

  @doc """
  Transfers all content from `from_user_id` to `to_user_id`.
  Updates all FK references except `users_tokens` (which are deleted).
  """
  @spec transfer_user_content(integer(), integer()) :: {:ok, map()} | {:error, any()}
  def transfer_user_content(from_user_id, to_user_id) do
    Brando.repo().transaction(fn ->
      refs = get_user_foreign_key_references()

      Enum.reduce(refs, %{}, fn {table, column}, acc ->
        if table == "users_tokens" do
          %{num_rows: num_rows} =
            Ecto.Adapters.SQL.query!(
              Brando.repo(),
              "DELETE FROM users_tokens WHERE user_id = $1",
              [from_user_id]
            )

          Map.put(acc, table, num_rows)
        else
          %{num_rows: num_rows} =
            Ecto.Adapters.SQL.query!(
              Brando.repo(),
              "UPDATE #{table} SET #{column} = $1 WHERE #{column} = $2",
              [to_user_id, from_user_id]
            )

          Map.put(acc, table, num_rows)
        end
      end)
    end)
  end

  @doc """
  Transfers all content from `user_id` to `transfer_to_user_id`,
  then soft-deletes the user.
  """
  @spec delete_user_with_transfer(integer(), integer(), user()) :: {:ok, User.t()} | {:error, any()}
  def delete_user_with_transfer(user_id, transfer_to_user_id, current_user) do
    with {:ok, _counts} <- transfer_user_content(user_id, transfer_to_user_id) do
      delete_user(user_id, current_user)
    end
  end

  def get_users_map do
    list_opts = %{
      select: [:id, :name, :last_login],
      cache: {:ttl, :infinite},
      preload: [{:avatar, :join}],
      order: [{:desc_nulls_last, :last_login}]
    }

    do_get_users_map(list_opts)
  end

  def get_users_map(user_ids) when is_list(user_ids) and user_ids != [] do
    list_opts = %{
      filter: %{ids: user_ids},
      select: [:id, :name, :last_login],
      cache: {:ttl, :infinite},
      preload: [{:avatar, :join}],
      order: [{:desc_nulls_last, :last_login}]
    }

    do_get_users_map(list_opts)
  end

  def get_users_map([]) do
    []
  end

  def do_get_users_map(list_opts) do
    {:ok, users} = Brando.Users.list_users(list_opts)

    Enum.map(
      users,
      fn user ->
        {user.id,
         %{
           name: user.name,
           id: user.id,
           avatar: user.avatar,
           last_login: user.last_login
         }}
      end
    )
  end
end

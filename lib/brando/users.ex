defmodule Brando.Users do
  @moduledoc """
  Context for Users.
  """
  use BrandoAdmin, :context
  use Brando.Query
  use Gettext, backend: Brando.Gettext

  import Ecto.Query

  require Logger

  alias Brando.Repo
  alias Brando.Users.User
  alias Brando.Users.UserNotifier
  alias Brando.Users.UserToken
  alias Brando.Utils
  alias Ecto.Changeset
  alias Ecto.Multi

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
  The user id a background job records for `user`: `nil` for `:system`,
  which work started outside the admin (a site's own upload form) runs as.
  """
  def job_user_id(:system), do: nil
  def job_user_id(%{id: id}), do: id

  @doc "The user a job was queued for, back from `job_user_id/1`."
  def get_job_user(nil), do: {:ok, :system}
  def get_job_user(user_id), do: get_user(user_id)

  @doc """
  Bumps `user`'s `last_login` to current time.

  Called once, from the login controller. It used to double as "last seen",
  which is what `set_last_seen/1` is for now.
  """
  @spec set_last_login(user) :: {:ok, user}
  def set_last_login(user) do
    current_time = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    Utils.Schema.update_field(user, last_login: current_time)
  end

  @doc """
  Bumps `user`'s `last_seen` to current time.

  Called from the admin presence tracker when a user's last admin session goes
  away. A remembered session can keep somebody signed in for months, so
  `last_login` is no guide at all to when they were last actually here.

  The module is deliberately named in prose rather than as a reference: it
  carries `@moduledoc false`, and ExDoc treats a link to a hidden module as a
  warning — which `mix docs --warnings-as-errors` in CI turns into a failure.
  """
  @spec set_last_seen(user) :: {:ok, user}
  def set_last_seen(user) do
    current_time = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    Utils.Schema.update_field(user, last_seen: current_time)
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
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)

    query
    |> Repo.one()
    |> Repo.preload(:avatar)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_session_token(token) do
    Repo.delete_all(UserToken.token_and_context_query(token, "session"))
    :ok
  end

  @doc """
  The id of the LiveView sockets of the session `token`, which
  the login puts in the session. Broadcasting `"disconnect"` to it
  closes them.
  """
  @spec live_socket_id(binary()) :: String.t()
  def live_socket_id(token), do: "users_sessions:#{Base.url_encode64(token)}"

  def build_token(id) do
    Phoenix.Token.sign(Brando.endpoint(), "user_token", id)
  end

  def verify_token(token) do
    Phoenix.Token.verify(Brando.endpoint(), "user_token", token, max_age: 86_400)
  end

  ## Passwords

  @doc """
  The admin's page to ask for a password reset link, or, with `token`, the
  link itself.
  """
  @spec reset_password_url(String.t() | nil) :: String.t()
  def reset_password_url(token \\ nil) do
    base = String.trim_trailing(Brando.endpoint().url(), "/") <> "/admin/reset-password"
    if token, do: base <> "/" <> token, else: base
  end

  @doc """
  Asks for a password reset link for the account with `email`.

  The answer is the same whether or not there is such an account: the lookup
  and the email happen in a background job (`Brando.Worker.PasswordReset`), so
  neither the reply nor the time it takes tells anything. Only an active,
  undeleted account gets an email.

  Returns `:ok`, or — without a mailer or sender, in production —
  `{:error, :no_mailer}` or `{:error, :no_sender}`. Development and test raise
  instead, see `Brando.Mailer.ensure_configured/0`.
  """
  @spec request_password_reset(String.t()) :: :ok | {:error, :no_mailer | :no_sender}
  def request_password_reset(email) when is_binary(email) do
    with :ok <- Brando.Mailer.ensure_configured() do
      {:ok, _job} =
        %{"email" => email |> String.trim() |> String.slice(0, 160)}
        |> Brando.Tenant.Job.attach_current()
        |> Brando.Worker.PasswordReset.new()
        |> Oban.insert()

      :ok
    end
  end

  @doc """
  Emails a password reset link to the active, undeleted account with `email`,
  if there is one. Run by `Brando.Worker.PasswordReset`; returns `:ok` either
  way, or `{:error, reason}` when the email could not be queued.
  """
  @spec deliver_password_reset(String.t()) :: :ok | {:error, term()}
  def deliver_password_reset(email) when is_binary(email) do
    query = from u in User, where: u.email == ^email and u.active == true and is_nil(u.deleted_at)

    case Repo.one(query) do
      nil -> :ok
      user -> user |> deliver_reset_link(:requested) |> ok()
    end
  end

  @doc """
  Sends `user_id` a link to choose a new password, on behalf of
  `current_user`. A superuser may send one to anyone, others only to
  themselves, and only an active account gets one.

  Returns `{:ok, user}`, or `{:error, reason}`: `:forbidden`, `:inactive`, an
  unknown user, or no mailer or sender in production.
  """
  @spec send_password_reset(integer() | String.t(), user) :: {:ok, user} | {:error, term()}
  def send_password_reset(user_id, current_user) do
    with {:ok, user} <- get_user(user_id),
         :ok <- check(Brando.Trait.ProtectPassword.allowed?(current_user, user), :forbidden),
         :ok <- check(user.active, :inactive),
         :ok <- Brando.Mailer.ensure_configured(),
         {:ok, _job} <- deliver_reset_link(user, :admin) do
      {:ok, user}
    end
  end

  # Only the newest link works: one sent earlier, either way, is deleted.
  defp deliver_reset_link(user, reason) do
    context = if reason == :admin, do: "admin_reset_password", else: "reset_password"
    {encoded, user_token} = UserToken.build_email_token(user, context)

    Repo.transaction(fn ->
      Repo.delete_all(UserToken.user_and_contexts_query(user, UserToken.reset_password_contexts()))
      Repo.insert!(user_token)
    end)

    UserNotifier.deliver_reset_password_instructions(user, reset_password_url(encoded), reason)
  end

  defp check(true, _reason), do: :ok
  defp check(_, reason), do: {:error, reason}

  defp ok({:ok, _}), do: :ok
  defp ok(error), do: error

  @doc """
  The active, undeleted user the password reset `token` was sent to, while
  the link is valid, or nil.
  """
  @spec get_user_by_reset_password_token(String.t()) :: user | nil
  def get_user_by_reset_password_token(token) when is_binary(token) do
    case UserToken.verify_reset_password_token_query(token) do
      {:ok, query} -> Repo.one(query)
      :error -> nil
    end
  end

  def get_user_by_reset_password_token(_token), do: nil

  @doc """
  A changeset for a new password: `password` and a matching
  `password_confirmation`, checked against the `User` blueprint's password
  constraints. Nothing else in `attrs` is cast.
  """
  @spec password_changeset(user, map()) :: Changeset.t()
  def password_changeset(%User{} = user, attrs \\ %{}) do
    password = Brando.Blueprint.Attributes.__attribute__(User, :password)
    password = %{password | opts: Map.update(password.opts, :constraints, [], &Keyword.delete(&1, :confirmation))}

    user
    |> Changeset.cast(attrs, [:password])
    |> Changeset.validate_required([:password])
    |> Brando.Blueprint.Constraints.run_validations(User, [password])
    # Bcrypt only reads the first 72 bytes
    |> Changeset.validate_length(:password, max: 72, count: :bytes)
    |> Changeset.validate_confirmation(:password, required: true)
  end

  @doc """
  Sets the password of `user`, who opened a valid reset link, to the one in
  `attrs` (see `password_changeset/2`).

  Logs the user out everywhere: every token is deleted — sessions, and the
  reset link with any other — and their open admin views are disconnected.
  The user is emailed that the password changed.
  """
  @spec reset_user_password(user, map()) :: {:ok, user} | {:error, Changeset.t()}
  def reset_user_password(%User{} = user, attrs) do
    user
    |> password_changeset(attrs)
    |> save_password(UserToken.user_and_contexts_query(user, :all))
  end

  @doc """
  Changes the password of the logged-in `user`, who must give their
  `current_password`, to the one in `attrs` (see `password_changeset/2`).

  Logs the user out of every other session, keeping `current_token` — the
  session token of the browser doing the change — and deletes any password
  reset link. The user is emailed that the password changed.
  """
  @spec update_user_password(user, String.t() | nil, map(), binary() | nil) ::
          {:ok, user} | {:error, Changeset.t()}
  def update_user_password(%User{} = user, current_password, attrs, current_token \\ nil) do
    revoked =
      if current_token,
        do: from(t in UserToken.user_and_contexts_query(user, :all), where: t.token != ^current_token),
        else: UserToken.user_and_contexts_query(user, :all)

    user
    |> password_changeset(attrs)
    |> validate_current_password(current_password)
    |> save_password(revoked)
  end

  @doc """
  Sets the password of the user `user_id` to the one in `attrs` (see
  `password_changeset/2`), on behalf of `current_user`: the fallback for a
  site that cannot email a reset link.

  Only a superuser may, and not for their own account, which changes with
  `update_user_password/4`. The user is logged out everywhere, emailed that
  an administrator set their password when a mailer is configured, and must
  choose their own password the next time they log in
  (`reset_password_on_first_login`).

  Returns `{:ok, user}`, `{:error, changeset}`, or `{:error, reason}`:
  `:forbidden` or an unknown user.
  """
  @spec set_user_password(integer() | String.t(), map(), user) ::
          {:ok, user} | {:error, Changeset.t() | term()}
  def set_user_password(user_id, attrs, current_user) do
    with {:ok, user} <- get_user(user_id),
         :ok <- check(not same_user?(user, current_user), :forbidden),
         :ok <- check(Brando.Trait.ProtectPassword.allowed?(current_user, user), :forbidden) do
      user
      |> password_changeset(attrs)
      |> save_password(UserToken.user_and_contexts_query(user, :all), :admin)
    end
  end

  defp same_user?(%{id: id}, %{id: id}), do: true
  defp same_user?(_user, _other), do: false

  defp validate_current_password(changeset, password) do
    if is_binary(password) and Bcrypt.verify_pass(password, changeset.data.password) do
      changeset
    else
      Changeset.add_error(changeset, :current_password, gettext("is not your current password"))
    end
  end

  # A password the user chose clears the first-login change; one an
  # administrator set (`by: :admin`) asks for it.
  defp save_password(changeset, revoked_tokens, by \\ :user)

  defp save_password(%Changeset{valid?: true} = changeset, revoked_tokens, by) do
    changeset =
      changeset
      |> Changeset.put_embed(:config, %{reset_password_on_first_login: by == :admin})
      |> Changeset.prepare_changes(&Brando.Trait.Password.hash_password/1)

    Multi.new()
    |> Multi.update(:user, changeset)
    |> Multi.delete_all(:tokens, from(t in revoked_tokens, select: {t.context, t.token}))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user, tokens: {_count, tokens}}} ->
        for {"session", token} <- tokens, do: Brando.endpoint().broadcast(live_socket_id(token), "disconnect", %{})
        notify_password_changed(user, by)
        {:ok, user}

      {:error, :user, changeset, _} ->
        {:error, changeset}
    end
  end

  defp save_password(changeset, _revoked_tokens, _by), do: {:error, Map.put(changeset, :action, :update)}

  # Without a mailer the password is still changed; there is just no email.
  defp notify_password_changed(user, by) do
    if Brando.Mailer.configured?() and not is_nil(Brando.Mailer.sender()[:from]) do
      UserNotifier.deliver_password_changed(user, by)
    else
      Logger.info("[Brando.Users] No email sent about the changed password of user ##{user.id}: no mailer configured")
    end
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

  A row that references the user from several columns (say `creator_id` and
  `updated_by_id`) is counted once.
  """
  @spec get_user_content_summary(integer()) :: [map()]
  def get_user_content_summary(user_id) do
    get_user_foreign_key_references()
    |> Enum.reject(fn {table, _column} ->
      table in ["users_tokens", "user_sites", "activity_events"] or String.starts_with?(table, "authorization_")
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {table, columns} ->
      matches = Enum.map_join(columns, " OR ", &"#{&1} = $1")

      %{rows: [[count]]} =
        Ecto.Adapters.SQL.query!(Brando.repo(), "SELECT count(*) FROM #{table} WHERE #{matches}", [user_id])

      %{table: table, columns: columns, count: count}
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
        num_rows = transfer_or_delete_ref(table, column, from_user_id, to_user_id)
        Map.put(acc, table, num_rows)
      end)
    end)
  end

  defp transfer_or_delete_ref("users_tokens", _column, from_user_id, _to_user_id) do
    %{num_rows: num_rows} =
      Ecto.Adapters.SQL.query!(
        Brando.repo(),
        "DELETE FROM users_tokens WHERE user_id = $1",
        [from_user_id]
      )

    num_rows
  end

  defp transfer_or_delete_ref("authorization_" <> _, _column, _from, _to), do: 0
  defp transfer_or_delete_ref("user_sites", _column, _from, _to), do: 0
  # The activity log records who did what; handing it to another user would rewrite history.
  defp transfer_or_delete_ref("activity_events", _column, _from, _to), do: 0

  defp transfer_or_delete_ref(table, column, from_user_id, to_user_id) do
    %{num_rows: num_rows} =
      Ecto.Adapters.SQL.query!(
        Brando.repo(),
        "UPDATE #{table} SET #{column} = $1 WHERE #{column} = $2",
        [to_user_id, from_user_id]
      )

    num_rows
  end

  @doc """
  Transfers all content from `user_id` to `transfer_to_user_id`,
  then soft-deletes the user.
  """
  @spec delete_user_with_transfer(integer(), integer(), user()) :: {:ok, User.t()} | {:error, any()}
  def delete_user_with_transfer(user_id, transfer_to_user_id, current_user) do
    Brando.Authorization.Boundary.run(current_user, :delete, User, fn actor ->
      with {:ok, user} <- get_user(user_id),
           :ok <- Brando.Authorization.Boundary.authorize(actor, :delete, user),
           :ok <- protect_account(user),
           {:ok, _counts} <- transfer_user_content(user_id, transfer_to_user_id) do
        delete_user(user_id, actor)
      end
    end)
  end

  defp protect_account(user) do
    if Brando.Authorization.enabled?(), do: Brando.Authorization.Groups.protect_account!(user.id), else: :ok
  end

  def get_users_map do
    list_opts = %{
      select: [:id, :name, :last_login, :last_seen],
      cache: {:ttl, :infinite},
      preload: [{:avatar, :join}],
      order: [{:desc_nulls_last, :last_seen}]
    }

    do_get_users_map(list_opts)
  end

  def get_users_map(user_ids) when is_list(user_ids) and user_ids != [] do
    list_opts = %{
      filter: %{ids: user_ids},
      select: [:id, :name, :last_login, :last_seen],
      cache: {:ttl, :infinite},
      preload: [{:avatar, :join}],
      order: [{:desc_nulls_last, :last_seen}]
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
           last_login: user.last_login,
           last_seen: user.last_seen
         }}
      end
    )
  end
end

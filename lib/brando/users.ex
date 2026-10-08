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
  alias Brando.Users.SecurityLog
  alias Brando.Users.TwoFactor
  alias Brando.Users.User
  alias Brando.Users.UserNotifier
  alias Brando.Users.UserToken
  alias Brando.Utils
  alias Ecto.Changeset
  alias Ecto.Multi

  @type user :: User.t()

  # A user's sign-in security, which is theirs alone: content transfer leaves it out.
  @security_tables [
    "users_security",
    "users_recovery_codes",
    "users_passkeys",
    "users_security_events",
    "users_security_policy"
  ]

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

  # A deactivated or deleted account cannot log in, and nor may its open
  # admin views and sockets go on: its sessions end with it, and so do the
  # tools it connected over MCP.
  mutation :update, User do
    fn entry ->
      if entry.active == false or not is_nil(entry.deleted_at) do
        revoke_sessions(entry)
        Repo.after_commit(fn -> Brando.MCP.revoke_user_grants(entry, "account_deactivated") end)
      end

      {:ok, entry}
    end
  end

  mutation :delete, User do
    fn entry ->
      revoke_sessions(entry)
      Repo.after_commit(fn -> Brando.MCP.revoke_user_grants(entry, "account_deleted") end)
      {:ok, entry}
    end
  end

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
  Whether `user` is a superuser: in the installation's superuser group with
  groups authorization, or of the `:superuser` role without.
  """
  @spec superuser?(user | term()) :: boolean()
  def superuser?(%User{} = user) do
    if Brando.Authorization.enabled?(),
      do: Brando.Authorization.Engine.superuser?(Brando.Authorization.Scope.installation(user)),
      else: user.role == :superuser
  end

  def superuser?(_), do: false

  @doc """
  Generates a session token, noting the browser and address of `meta`
  (`Brando.Users.SecurityLog.meta/1`) for the user's list of sessions. A
  new session has just given its password (and second factor), so it counts
  as confirmed (`confirm_session/1`).
  """
  def generate_user_session_token(user, meta \\ %{}) do
    {token, user_token} = UserToken.build_session_token(user, meta)
    Repo.insert!(user_token)
    token
  end

  ## Sessions

  @doc "`user`'s sessions, most recently used first."
  @spec list_sessions(user) :: [UserToken.t()]
  def list_sessions(%{id: user_id}) do
    days = UserToken.session_validity_in_days()

    # Without the token itself, which stays out of the caller's state
    from(t in UserToken,
      where: t.user_id == ^user_id and t.context == "session" and t.inserted_at > ago(^days, "day"),
      order_by: [desc_nulls_last: t.last_used_at, desc: t.inserted_at],
      select: struct(t, [:id, :user_id, :context, :ip, :user_agent, :inserted_at, :last_used_at, :confirmed_at])
    )
    |> Repo.all()
  end

  @doc """
  Logs out `user`'s session `session_id` (the token row's id, not the
  token). Returns `:ok`, or `{:error, :not_found}` for a session that is not
  theirs.
  """
  @spec revoke_session(user, integer() | String.t(), keyword()) :: :ok | {:error, :not_found}
  def revoke_session(%{id: user_id} = user, session_id, opts \\ []) do
    query = from t in UserToken, where: t.id == ^session_id and t.user_id == ^user_id and t.context == "session"

    case Repo.delete_all(from(t in query, select: t.token)) do
      {1, [token]} ->
        disconnect_session(token)
        SecurityLog.record(:session_revoked, user, meta: opts[:meta])
        :ok

      _ ->
        {:error, :not_found}
    end
  end

  @doc """
  Logs `user` out everywhere on behalf of `actor`: an administrator allowed
  to reset the user's password (`Brando.Trait.ProtectPassword.allowed?/2`),
  or the user themselves, who keeps the session with the token row id
  `opts[:except_id]`. The tools the user connected over MCP are
  disconnected too (`Brando.MCP.revoke_user_grants/2`).
  """
  @spec log_out_everywhere(user, user, keyword()) :: :ok | {:error, :forbidden}
  def log_out_everywhere(user, actor, opts \\ []) do
    if Brando.Trait.ProtectPassword.allowed?(actor, user) do
      revoke_sessions(user, except_id: opts[:except_id])
      # Everywhere includes the tools connected over MCP.
      Repo.after_commit(fn -> Brando.MCP.revoke_user_grants(user, "logged_out_everywhere") end)
      SecurityLog.record(:sessions_revoked, user, actor: actor, meta: opts[:meta])
      :ok
    else
      {:error, :forbidden}
    end
  end

  @doc """
  Notes that the session `token` is in use, at most every five minutes, for
  the list of sessions.
  """
  @spec touch_session(binary() | nil) :: :ok
  def touch_session(token) when is_binary(token) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    stale = NaiveDateTime.add(now, -300, :second)

    from(t in UserToken,
      where: t.token == ^token and t.context == "session",
      where: is_nil(t.last_used_at) or t.last_used_at < ^stale
    )
    |> Repo.update_all(set: [last_used_at: now])

    :ok
  end

  def touch_session(_token), do: :ok

  @doc """
  Notes that the session `token` has just given a password, a code or a
  passkey again (see `BrandoAdmin.Reauth`).
  """
  @spec confirm_session(binary() | integer()) :: :ok
  def confirm_session(token_or_id) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    Repo.update_all(session_query(token_or_id), set: [confirmed_at: now])
    :ok
  end

  @doc """
  When the session (its token, or its token row's id) last gave a password,
  a code or a passkey, or nil.
  """
  @spec session_confirmed_at(binary() | integer() | nil) :: NaiveDateTime.t() | nil
  def session_confirmed_at(nil), do: nil
  def session_confirmed_at(token_or_id), do: Repo.one(from t in session_query(token_or_id), select: t.confirmed_at)

  @doc "Whether the session (its token, or its token row's id) gave a password, a code or a passkey in the last `seconds`."
  @spec session_confirmed_within?(binary() | integer() | nil, pos_integer()) :: boolean()
  def session_confirmed_within?(token_or_id, seconds) when is_binary(token_or_id) or is_integer(token_or_id) do
    since = NaiveDateTime.add(NaiveDateTime.utc_now(), -seconds, :second)
    Repo.repo().exists?(from t in session_query(token_or_id), where: t.confirmed_at > ^since)
  end

  def session_confirmed_within?(_token, _seconds), do: false

  defp session_query(id) when is_integer(id), do: from(t in UserToken, where: t.id == ^id and t.context == "session")
  defp session_query(token) when is_binary(token), do: UserToken.token_and_context_query(token, "session")

  @doc """
  Gets the user with the given signed token.

  A user whom the sign-in policy now requires to use two-factor
  authentication, and who has not set it up, gets nil, and the session ends:
  they set it up at their next sign-in (`Brando.Users.TwoFactor.must_enroll?/1`).
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)

    case Repo.one(query) do
      nil ->
        nil

      user ->
        if TwoFactor.must_enroll?(user) do
          end_session(token)
          nil
        else
          Repo.preload(user, :avatar)
        end
    end
  end

  defp end_session(token) do
    delete_session_token(token)
    disconnect_session(token)
  end

  @doc """
  Logs `user` out of every session, and ends any sign-in waiting for its
  second step, but the token row `opts[:except_id]` (the current session, or
  the waiting sign-in that is setting two-factor authentication up). Their
  open admin views are disconnected.
  """
  @spec revoke_sessions(user, keyword()) :: :ok
  def revoke_sessions(%{id: _} = user, opts \\ []) do
    query = UserToken.user_and_contexts_query(user, ["session" | UserToken.pending_contexts()])

    query =
      case opts[:except_id] do
        nil -> query
        id -> from t in query, where: t.id != ^id
      end

    {_count, tokens} = Repo.delete_all(from(t in query, select: {t.context, t.token, t.id}))
    announce_deleted(tokens)
  end

  # Tells whoever holds a deleted token: a session's open admin views are
  # disconnected, and a waiting sign-in's setup screen is closed.
  defp announce_deleted(tokens) do
    for {context, token, id} <- tokens do
      cond do
        context == "session" ->
          disconnect_session(token)

        context in UserToken.pending_contexts() ->
          announce_pending_ended(id)

        true ->
          :ok
      end
    end

    :ok
  end

  # Once committed, like disconnect_session/1
  defp announce_pending_ended(id) do
    Repo.after_commit(fn ->
      Phoenix.PubSub.broadcast(Brando.pubsub(), pending_login_topic(id), {:pending_login_ended, id})
    end)
  end

  @doc """
  The PubSub topic a waiting sign-in's screens listen on, told
  `{:pending_login_ended, id}` when its token row `id` is deleted — by a
  password change, a reset, or logging the user out everywhere.
  """
  @spec pending_login_topic(integer()) :: String.t()
  def pending_login_topic(id), do: "users_pending_logins:#{id}"

  @doc """
  The id of the token row of `token` in `context`, or nil. LiveViews keep
  this rather than the token itself, so the token does not end up in their
  state.
  """
  @spec token_id(binary() | nil, String.t() | [String.t()]) :: integer() | nil
  def token_id(token, contexts \\ "session")

  def token_id(token, contexts) when is_binary(token) do
    Repo.one(from t in UserToken, where: t.token == ^token and t.context in ^List.wrap(contexts), select: t.id)
  end

  def token_id(_token, _contexts), do: nil

  ## Sign-in waiting for its second step

  @doc """
  Starts a sign-in whose password was right but which waits for a
  two-factor code, or for the user to set two-factor authentication up.
  Returns the token to keep in the session; it is not a session token.
  Any earlier such sign-in of the user ends.
  """
  @spec generate_pending_token(user) :: binary()
  def generate_pending_token(user) do
    {token, user_token} = UserToken.build_pending_token(user)

    {:ok, ended} =
      Repo.transaction(fn ->
        query = UserToken.user_and_contexts_query(user, UserToken.pending_contexts())
        {_count, ended} = Repo.delete_all(from(t in query, select: {t.context, t.token, t.id}))
        Repo.insert!(user_token)
        ended
      end)

    announce_deleted(ended)
    token
  end

  @doc """
  The user of a sign-in waiting for its second step, and whether they have
  just set two-factor authentication up (`:verified`) or must give a code
  (`:pending`): `{user, state}`, or nil when the token is unknown or older
  than `Brando.Users.UserToken.pending_validity_in_minutes/0`.
  """
  @spec get_pending_login(binary() | nil) :: {user, :pending | :verified} | nil
  def get_pending_login(token) when is_binary(token) do
    case Repo.one(UserToken.verify_pending_token_query(token)) do
      {user, "pending_2fa"} -> {user, :pending}
      {user, "two_factor_verified"} -> {user, :verified}
      nil -> nil
    end
  end

  def get_pending_login(_token), do: nil

  @doc """
  Whether the token row `id` is still `user`'s sign-in waiting for its
  second step: not used, not ended by a password change or reset, and not
  older than `Brando.Users.UserToken.pending_validity_in_minutes/0`; and the
  account still active. The setup screen of a sign-in checks this before
  anything it adds, since only the sign-in vouches for the user there.
  """
  @spec pending_login_valid?(integer() | nil, user) :: boolean()
  def pending_login_valid?(id, %{id: user_id}) when is_integer(id) do
    minutes = UserToken.pending_validity_in_minutes()

    Repo.repo().exists?(
      from t in UserToken,
        join: u in assoc(t, :user),
        where: t.id == ^id and t.user_id == ^user_id and t.context == "pending_2fa",
        where: t.inserted_at > ago(^minutes, "minute"),
        where: u.active == true and is_nil(u.deleted_at)
    )
  end

  def pending_login_valid?(_id, _user), do: false

  @doc """
  Marks the sign-in waiting for its second step with the token row `id` as
  done: the user has just set two-factor authentication up.
  """
  @spec verify_pending_login(integer()) :: :ok | :error
  def verify_pending_login(id) when is_integer(id) do
    query = from t in UserToken, where: t.id == ^id and t.context == "pending_2fa"

    case Repo.update_all(query, set: [context: "two_factor_verified"]) do
      {1, _} -> :ok
      _ -> :error
    end
  end

  @doc "Ends a sign-in waiting for its second step."
  @spec delete_pending_token(binary() | nil) :: :ok
  def delete_pending_token(token) when is_binary(token) do
    {_count, ended} =
      Repo.delete_all(
        from t in UserToken,
          where: t.token == ^token and t.context in ^UserToken.pending_contexts(),
          select: {t.context, t.token, t.id}
      )

    announce_deleted(ended)
  end

  def delete_pending_token(_token), do: :ok

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_session_token(token) do
    Repo.delete_all(UserToken.token_and_context_query(token, "session"))
    :ok
  end

  @doc """
  The id of the sockets of the session `token`: its LiveViews (the login
  puts the id in the session) and its admin socket
  (`BrandoAdmin.AdminSocket`). `disconnect_session/1` broadcasts
  `"disconnect"` to it.

  It is made from a SHA-256 hash of the token, so the token itself is in no
  socket's state, and no crash report that prints one.
  """
  @spec live_socket_id(binary()) :: String.t()
  def live_socket_id(token) when is_binary(token),
    do: "users_sessions:" <> Base.url_encode64(:crypto.hash(:sha256, token), padding: false)

  # The id before it was hashed, still in the session cookies of tabs
  # opened before the upgrade. TODO: remove in 0.56, with its broadcast in
  # disconnect_session/1 and its rewrite in BrandoAdmin.UserAuth.
  @doc false
  def legacy_live_socket_id(token) when is_binary(token), do: "users_sessions:#{Base.url_encode64(token)}"

  @doc """
  Disconnects every socket of the session `token` — its LiveViews and its
  admin socket — and no other session's. Call it once the session's token
  is deleted: the sockets try to reconnect, and are turned away. Inside a
  transaction (`Brando.Repo.transaction/2`) it waits for the commit, since a
  socket reconnecting before then would still find the session.
  """
  @spec disconnect_session(binary()) :: :ok
  def disconnect_session(token) when is_binary(token) do
    Repo.after_commit(fn ->
      endpoint = Brando.endpoint()
      endpoint.broadcast(live_socket_id(token), "disconnect", %{})
      # Tabs opened before the id was hashed. TODO: remove in 0.56
      endpoint.broadcast(legacy_live_socket_id(token), "disconnect", %{})
    end)
  end

  @doc """
  Whether `user_id`'s session with the token row id `session_id` is still
  valid (`verify_socket_token/1`). The admin socket's channels check it as
  they join: a session that ended between the socket's connect and its
  subscribing to `live_socket_id/1` would otherwise keep it.
  """
  @spec session_valid?(integer() | nil, integer() | nil) :: boolean()
  def session_valid?(session_id, user_id) when is_integer(session_id) and is_integer(user_id),
    do: Repo.repo().exists?(UserToken.verify_session_id_query(session_id, user_id))

  def session_valid?(_session_id, _user_id), do: false

  @socket_token_salt "brando_admin_socket"
  @socket_token_max_age 86_400

  @doc """
  A token for the admin socket (`BrandoAdmin.AdminSocket`) of `user`'s
  session with the token row id `session_id` (`token_id/2`).

  The page hands it to its JavaScript, so it holds no secret: it is signed,
  not encrypted, and names the session by its row id, never by its token. It
  is good for a day, and only while the session lasts: the socket checks
  that on every connect (`verify_socket_token/1`), and ending the session
  disconnects it (`live_socket_id/1`).
  """
  @spec build_socket_token(user | %{id: integer()}, integer()) :: String.t()
  def build_socket_token(%{id: user_id}, session_id) when is_integer(session_id) do
    Phoenix.Token.sign(Brando.endpoint(), @socket_token_salt, %{"user_id" => user_id, "session_id" => session_id})
  end

  @doc """
  The session behind an admin socket token (`build_socket_token/2`), while it
  is valid: `{:ok, %{user_id: id, session_id: id, socket_id: id}}`. A token
  older than a day, a session that has ended or expired, and an account
  deactivated or deleted since give `{:error, :invalid}`. `socket_id` is the
  session's `live_socket_id/1`, so ending the session disconnects the socket
  along with the session's LiveViews.
  """
  @spec verify_socket_token(String.t() | nil) :: {:ok, map()} | {:error, :invalid}
  def verify_socket_token(token) when is_binary(token) do
    with {:ok, %{"user_id" => user_id, "session_id" => session_id}}
         when is_integer(user_id) and is_integer(session_id) <-
           Phoenix.Token.verify(Brando.endpoint(), @socket_token_salt, token, max_age: @socket_token_max_age),
         session_token when is_binary(session_token) <-
           Repo.one(UserToken.verify_session_id_query(session_id, user_id)) do
      {:ok, %{user_id: user_id, session_id: session_id, socket_id: live_socket_id(session_token)}}
    else
      _ -> {:error, :invalid}
    end
  end

  def verify_socket_token(_token), do: {:error, :invalid}

  @deprecated "Not tied to a session, and no longer accepted by BrandoAdmin.AdminSocket: use build_socket_token/2"
  def build_token(id) do
    Phoenix.Token.sign(Brando.endpoint(), "user_token", id)
  end

  @deprecated "Not tied to a session: use verify_socket_token/1"
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
    |> log_password_change(%{"by" => "reset_link"})
  end

  @doc """
  Changes the password of the logged-in `user`, who must give their
  `current_password`, to the one in `attrs` (see `password_changeset/2`).

  Logs the user out of every other session, keeping `current` — the session
  token of the browser doing the change, or that session's token row id —
  and deletes any password reset link. The user is emailed that the password changed.
  """
  @spec update_user_password(user, String.t() | nil, map(), binary() | integer() | nil) ::
          {:ok, user} | {:error, Changeset.t()}
  def update_user_password(%User{} = user, current_password, attrs, current \\ nil) do
    all = UserToken.user_and_contexts_query(user, :all)

    revoked =
      cond do
        is_integer(current) -> from(t in all, where: t.id != ^current)
        is_binary(current) -> from(t in all, where: t.token != ^current)
        true -> all
      end

    user
    |> password_changeset(attrs)
    |> validate_current_password(current_password)
    |> save_password(revoked)
    |> log_password_change(%{"by" => "user"})
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
      |> log_password_change(%{"by" => "admin"}, current_user)
    end
  end

  defp log_password_change(result, details, actor \\ nil)

  defp log_password_change({:ok, user} = result, details, actor) do
    SecurityLog.record(:password_changed, user, actor: actor, details: details)
    result
  end

  defp log_password_change(result, _details, _actor), do: result

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
    |> Multi.delete_all(:tokens, from(t in revoked_tokens, select: {t.context, t.token, t.id}))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user, tokens: {_count, tokens}}} ->
        announce_deleted(tokens)
        # A new password ends the tools connected over MCP too: whoever knew
        # the old one may have connected them.
        Repo.after_commit(fn -> Brando.MCP.revoke_user_grants(user, "password_changed") end)
        notify_password_changed(user, by)
        {:ok, user}

      {:error, :user, changeset, _} ->
        {:error, changeset}
    end
  end

  defp save_password(changeset, _revoked_tokens, _by), do: {:error, Map.put(changeset, :action, :update)}

  @doc """
  Emails `user` about a change to how they log in
  (`Brando.Users.UserNotifier.deliver_security_notice/3`), when the site has
  a mailer. Without one, the change still happens, and is logged.
  """
  @spec notify_security(user, atom(), map()) :: :ok
  def notify_security(user, kind, details \\ %{}) do
    if Brando.Mailer.configured?() and not is_nil(Brando.Mailer.sender()[:from]) do
      _ = UserNotifier.deliver_security_notice(user, kind, details)
    else
      Logger.info("[Brando.Users] No email sent to user ##{user.id} about #{kind}: no mailer configured")
    end

    :ok
  end

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
      table in ["users_tokens", "user_sites", "activity_events", "entry_notes", "note_mentions"] or
        table in @security_tables or
        String.starts_with?(table, "authorization_")
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
    # Brando.Repo's: the sessions it ends are disconnected once it commits
    Repo.transaction(fn ->
      refs = get_user_foreign_key_references()

      Enum.reduce(refs, %{}, fn {table, column}, acc ->
        num_rows = transfer_or_delete_ref(table, column, from_user_id, to_user_id)
        Map.put(acc, table, num_rows)
      end)
    end)
  end

  # The user's sessions end, and their sockets are told (`announce_deleted/1`)
  defp transfer_or_delete_ref("users_tokens", "user_id", from_user_id, _to_user_id) do
    {num_rows, tokens} =
      Repo.delete_all(from(t in UserToken, where: t.user_id == ^from_user_id, select: {t.context, t.token, t.id}))

    announce_deleted(tokens)
    num_rows
  end

  defp transfer_or_delete_ref(table, "user_id", from_user_id, _to_user_id)
       when table in ["users_security", "users_recovery_codes", "users_passkeys"] do
    %{num_rows: num_rows} =
      Ecto.Adapters.SQL.query!(
        Brando.repo(),
        "DELETE FROM #{table} WHERE user_id = $1",
        [from_user_id]
      )

    num_rows
  end

  defp transfer_or_delete_ref("authorization_" <> _, _column, _from, _to), do: 0
  defp transfer_or_delete_ref("user_sites", _column, _from, _to), do: 0
  # The activity log records who did what; handing it to another user would rewrite history.
  defp transfer_or_delete_ref("activity_events", _column, _from, _to), do: 0
  # Likewise who wrote a note, resolved it or was mentioned in it (`Brando.Notes`).
  defp transfer_or_delete_ref("entry_notes", _column, _from, _to), do: 0
  defp transfer_or_delete_ref("note_mentions", _column, _from, _to), do: 0
  # The security log records who signed in and who changed what, and the policy who last saved it.
  defp transfer_or_delete_ref(table, _column, _from, _to) when table in @security_tables, do: 0

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

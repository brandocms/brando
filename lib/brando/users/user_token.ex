defmodule Brando.Users.UserToken do
  @moduledoc """
  Tokens that stand in for a user: a session after login, a sign-in waiting
  for its second step, and a password reset link.

  A session token lives in the signed session or remember-me cookie, so it is
  stored as it is. A reset token is emailed, so only its SHA-256 hash is
  stored: someone who reads the database cannot rebuild the link.
  """
  use Ecto.Schema
  import Ecto.Query

  @hash_algorithm :sha256
  @rand_size 32

  # Short: whoever can read the user's email can take over the account with
  # it. A link an administrator sends lasts a day, since the user did not ask
  # for it and may not be waiting for it.
  @reset_password_validity %{"reset_password" => 60, "admin_reset_password" => 24 * 60}
  @session_validity_in_days 60

  # A sign-in whose password was right, waiting for a two-factor code
  # (`"pending_2fa"`), or for the user to finish setting two-factor
  # authentication up (`"two_factor_verified"` once they have). It is not a
  # session: nothing but the second step accepts it.
  @pending_validity_in_minutes 10
  @pending_contexts ~w(pending_2fa two_factor_verified)

  @type t :: %__MODULE__{}

  @schema_prefix "public"

  schema "users_tokens" do
    field :token, :binary, redact: true
    field :context, :string
    field :sent_to, :string
    # A session's browser and address, when it was last used, and when it last
    # gave a password, a code or a passkey (see `BrandoAdmin.Reauth`)
    field :ip, :string
    field :user_agent, :string
    field :last_used_at, :naive_datetime
    field :confirmed_at, :naive_datetime
    belongs_to :user, Brando.Users.User

    timestamps(updated_at: false)
  end

  @doc """
  The contexts of password reset links: `"reset_password"` for one the user
  asked for, `"admin_reset_password"` for one an administrator sent.
  """
  @spec reset_password_contexts() :: [String.t()]
  def reset_password_contexts, do: Map.keys(@reset_password_validity)

  @doc "How long a password reset link of `context` works, in minutes."
  @spec reset_password_validity_in_minutes(String.t()) :: pos_integer()
  def reset_password_validity_in_minutes(context \\ "reset_password"),
    do: Map.fetch!(@reset_password_validity, context)

  @doc """
  Generates a token that will be stored in a signed place,
  such as session or cookie. As they are signed, those
  tokens do not need to be hashed.
  """
  def build_session_token(user, meta \\ %{}) do
    token = :crypto.strong_rand_bytes(@rand_size)
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    {token,
     %Brando.Users.UserToken{
       token: token,
       context: "session",
       user_id: user.id,
       ip: meta[:ip],
       user_agent: meta[:user_agent] && String.slice(meta[:user_agent], 0, 255),
       last_used_at: now,
       confirmed_at: now
     }}
  end

  @doc "How long a session lasts, in days."
  def session_validity_in_days, do: @session_validity_in_days

  @doc """
  Checks if the token is valid and returns its underlying lookup query.

  The query returns the user found by the token.
  """
  def verify_session_token_query(token) do
    query =
      from token in token_and_context_query(token, "session"),
        join: user in assoc(token, :user),
        where:
          token.inserted_at > ago(@session_validity_in_days, "day") and user.active == true and is_nil(user.deleted_at),
        select: user

    {:ok, query}
  end

  @doc """
  The query for the token of `user_id`'s session with the row id `id`, while
  the session is valid and the account active and undeleted, as
  `verify_session_token_query/1` checks it.
  """
  def verify_session_id_query(id, user_id) when is_integer(id) and is_integer(user_id) do
    from token in Brando.Users.UserToken,
      join: user in assoc(token, :user),
      where: token.id == ^id and token.user_id == ^user_id and token.context == "session",
      where:
        token.inserted_at > ago(@session_validity_in_days, "day") and user.active == true and is_nil(user.deleted_at),
      select: token.token
  end

  @doc """
  Generates the token of a sign-in waiting for its second step, kept in the
  signed session like a session token. `context` is `"pending_2fa"`.
  """
  def build_pending_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {token, %Brando.Users.UserToken{token: token, context: "pending_2fa", user_id: user.id}}
  end

  @doc """
  The query for the active, undeleted user of a sign-in waiting for its
  second step, while it is valid, with the token's context:
  `{user, context}`.
  """
  def verify_pending_token_query(token) when is_binary(token) do
    from t in Brando.Users.UserToken,
      join: user in assoc(t, :user),
      where: t.token == ^token and t.context in @pending_contexts,
      where: t.inserted_at > ago(@pending_validity_in_minutes, "minute"),
      where: user.active == true and is_nil(user.deleted_at),
      select: {user, t.context}
  end

  @doc "The contexts of a sign-in waiting for its second step."
  def pending_contexts, do: @pending_contexts

  @doc "How long a sign-in waits for its second step, in minutes."
  def pending_validity_in_minutes, do: @pending_validity_in_minutes

  @doc """
  Builds a token to email to `user`, and its hashed counterpart to store.

  Returns `{encoded, user_token}`: the URL-safe token for the link, and the
  `UserToken` holding its hash and the address it was sent to. The token stops
  working when the user's email changes.
  """
  def build_email_token(user, context) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %Brando.Users.UserToken{
       token: hashed_token,
       context: context,
       sent_to: user.email,
       user_id: user.id
     }}
  end

  @doc """
  The query for the active, undeleted user a password reset `token` was sent
  to, while it is valid for its context (see `reset_password_contexts/0`).
  Returns `{:ok, query}`, or `:error` for a token that cannot be one of ours.
  """
  def verify_reset_password_token_query(token) when is_binary(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} -> {:ok, reset_password_user_query(:crypto.hash(@hash_algorithm, decoded_token))}
      :error -> :error
    end
  end

  def verify_reset_password_token_query(_token), do: :error

  defp reset_password_user_query(hashed_token) do
    from token in Brando.Users.UserToken,
      join: user in assoc(token, :user),
      where: token.token == ^hashed_token,
      where: ^reset_password_valid(),
      where: token.sent_to == user.email and user.active == true and is_nil(user.deleted_at),
      select: user
  end

  # A reset context, while it is younger than that context allows
  defp reset_password_valid do
    Enum.reduce(@reset_password_validity, dynamic(false), fn {context, minutes}, valid ->
      dynamic([token], ^valid or (token.context == ^context and token.inserted_at > ago(^minutes, "minute")))
    end)
  end

  @doc """
  Returns the given token with the given context.
  """
  def token_and_context_query(token, context) do
    from Brando.Users.UserToken, where: [token: ^token, context: ^context]
  end

  @doc """
  Gets all tokens for the given user for the given contexts.
  """
  def user_and_contexts_query(user, :all) do
    from t in Brando.Users.UserToken, where: t.user_id == ^user.id
  end

  def user_and_contexts_query(user, [_ | _] = contexts) do
    from t in Brando.Users.UserToken, where: t.user_id == ^user.id and t.context in ^contexts
  end
end

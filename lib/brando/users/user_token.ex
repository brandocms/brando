defmodule Brando.Users.UserToken do
  @moduledoc """
  Tokens that stand in for a user: a session after login, and a password
  reset link.

  A session token lives in the signed session or remember-me cookie, so it is
  stored as it is. A reset token is emailed, so only its SHA-256 hash is
  stored: someone who reads the database cannot rebuild the link.
  """
  use Ecto.Schema
  import Ecto.Query

  @hash_algorithm :sha256
  @rand_size 32

  # Short: whoever can read the user's email can take over the account with it.
  @reset_password_validity_in_minutes 60
  @session_validity_in_days 60

  @schema_prefix "public"

  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    belongs_to :user, Brando.Users.User

    timestamps(updated_at: false)
  end

  @doc "How long a password reset link works, in minutes."
  @spec reset_password_validity_in_minutes() :: pos_integer()
  def reset_password_validity_in_minutes, do: @reset_password_validity_in_minutes

  @doc """
  Generates a token that will be stored in a signed place,
  such as session or cookie. As they are signed, those
  tokens do not need to be hashed.
  """
  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {token, %Brando.Users.UserToken{token: token, context: "session", user_id: user.id}}
  end

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
  The query for the active, undeleted user an emailed `token` was sent to,
  while it is valid. Returns `{:ok, query}`, or `:error` for a token that
  cannot be one of ours.
  """
  def verify_email_token_query(token, "reset_password" = context) when is_binary(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from token in token_and_context_query(hashed_token, context),
            join: user in assoc(token, :user),
            where:
              token.inserted_at > ago(@reset_password_validity_in_minutes, "minute") and
                token.sent_to == user.email and user.active == true and is_nil(user.deleted_at),
            select: user

        {:ok, query}

      :error ->
        :error
    end
  end

  def verify_email_token_query(_token, _context), do: :error

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

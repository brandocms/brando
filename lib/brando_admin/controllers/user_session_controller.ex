defmodule BrandoAdmin.UserSessionController do
  use BrandoAdmin, :controller
  use Gettext, backend: Brando.Gettext

  alias Brando.Users
  alias Brando.Users.Passkeys
  alias Brando.Users.SecurityLog
  alias Brando.Users.Throttle
  alias Brando.Users.TwoFactor
  alias BrandoAdmin.UserAuth

  def create(conn, %{"user" => %{"email" => email, "password" => password} = user_params}) do
    meta = SecurityLog.meta(conn)

    case Throttle.check_login(meta.ip, email) do
      :ok -> check_account(conn, email, password, user_params, meta)
      {:error, :rate_limited, retry_after} -> too_many(conn, email, div(retry_after, 60_000) + 1)
    end
  end

  defp check_account(conn, email, password, user_params, meta) do
    case Users.get_user(%{matches: %{email: email, active: true}}) do
      {:ok, user} -> check_password(conn, user, password, user_params, meta)
      _ -> unknown_account(conn, email)
    end
  end

  # The password is checked even for a locked account, so the time taken
  # tells nothing, but a locked account does not sign in, right password or
  # not: otherwise the answer would tell a guesser when they got it right.
  defp check_password(conn, user, password, user_params, meta) do
    valid? = Bcrypt.verify_pass(password, user.password)

    cond do
      until = Throttle.locked_until(user) ->
        too_many(conn, user_params["email"], minutes_until(until))

      valid? ->
        UserAuth.after_password(conn, user, user_params)

      true ->
        case Throttle.failed(user, :password, meta) do
          :ok -> invalid(conn, user_params["email"])
          {:locked, until} -> too_many(conn, user_params["email"], minutes_until(until))
        end
    end
  end

  # Takes as long as checking a password, and answers as an account would
  # after as many failures, so neither tells whether the account exists.
  defp unknown_account(conn, email) do
    Bcrypt.no_user_verify()

    if until = Throttle.unknown_locked_until(email) do
      too_many(conn, email, minutes_until(until))
    else
      case Throttle.failed_unknown(email) do
        {:locked, until} -> too_many(conn, email, minutes_until(until))
        :ok -> invalid(conn, email)
      end
    end
  end

  @doc """
  The second step of a sign-in: a code from the user's authenticator app, or
  a recovery code.
  """
  def two_factor(conn, params) do
    code = get_in(params, ["two_factor", "code"])
    meta = SecurityLog.meta(conn)

    with {user, :pending} <- UserAuth.pending_login(conn),
         :ok <- Throttle.check_two_factor(meta.ip) do
      check_code(conn, user, code, meta)
    else
      {:error, :rate_limited, retry_after} ->
        conn
        |> put_flash(:error, too_many_message(div(retry_after, 60_000) + 1))
        |> redirect(to: "/admin/login/two-factor")

      _ ->
        UserAuth.abandon_pending_login(conn, expired_message())
    end
  end

  defp check_code(conn, user, code, meta) do
    with nil <- Throttle.locked_until(user),
         {:ok, method} <- TwoFactor.verify(user, code) do
      UserAuth.complete_pending_login(conn, user, method)
    else
      %DateTime{} = until -> UserAuth.abandon_pending_login(conn, too_many_message(minutes_until(until)))
      {:error, :invalid} -> wrong_code(conn, user, meta)
      {:error, :unreadable} -> unreadable_code(conn)
    end
  end

  # The site cannot decrypt the secret (its encryption secret changed): not
  # the user's fault, so not counted towards the lockout. Logged by TwoFactor.
  defp unreadable_code(conn) do
    conn
    |> put_flash(
      :error,
      gettext(
        "Codes from your app cannot be checked on this site right now. Use a recovery code, or ask an administrator to reset two-factor authentication."
      )
    )
    |> redirect(to: "/admin/login/two-factor")
  end

  defp wrong_code(conn, user, meta) do
    case Throttle.failed(user, :two_factor, meta) do
      :ok ->
        conn
        |> put_flash(:error, gettext("That code did not work. Check your app and try again."))
        |> redirect(to: "/admin/login/two-factor")

      {:locked, until} ->
        UserAuth.abandon_pending_login(conn, too_many_message(minutes_until(until)))
    end
  end

  @doc """
  Finishes the sign-in of a user who has just set two-factor authentication
  up on the way in, on the screen at `/admin/login/two-factor/setup`.
  """
  def complete_setup(conn, _params) do
    case UserAuth.pending_login(conn) do
      {user, :verified} -> UserAuth.complete_pending_login(conn, user, :two_factor_setup)
      {_user, :pending} -> redirect(conn, to: "/admin/login/two-factor/setup")
      nil -> UserAuth.abandon_pending_login(conn, expired_message())
    end
  end

  @doc """
  Options for a passkey on the login screens, as JSON: for the second step
  of a waiting sign-in (`"mode" => "second_factor"`), the user's passkeys;
  otherwise any passkey for this site the device holds, to log in with it
  alone. The challenge waits in the session for `passkey/2`, and answers once.
  """
  def passkey_options(conn, params) do
    mode = if params["mode"] == "second_factor", do: "second_factor", else: "passwordless"

    case passkey_subject(conn, mode) do
      nil ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "expired"})

      subject ->
        {challenge, options} = Passkeys.authentication_challenge(subject)

        conn
        |> put_session(:passkey_challenge, %{
          "bytes" => Base.encode64(challenge.bytes),
          "issued_at" => challenge.issued_at,
          "mode" => mode
        })
        |> json(%{publicKey: options})
    end
  end

  defp passkey_subject(conn, "second_factor") do
    case UserAuth.pending_login(conn) do
      {user, :pending} -> user
      _ -> nil
    end
  end

  defp passkey_subject(_conn, "passwordless"), do: :discoverable

  @doc """
  Logs in with a passkey: the second step of a waiting sign-in, or on its
  own. The browser's answer comes in `passkey`, Base64url-encoded.
  """
  def passkey(conn, %{"passkey" => result} = params) when is_map(result) do
    meta = SecurityLog.meta(conn)
    state = get_session(conn, :passkey_challenge)
    conn = delete_session(conn, :passkey_challenge)

    with :ok <- Throttle.check_two_factor(meta.ip),
         %{"bytes" => bytes, "issued_at" => issued_at, "mode" => mode} <- state,
         {:ok, bytes} <- Base.decode64(bytes) do
      passkey_login(conn, mode, bytes, issued_at, result, params, meta)
    else
      {:error, :rate_limited, retry_after} ->
        conn
        |> put_flash(:error, too_many_message(div(retry_after, 60_000) + 1))
        |> redirect(to: "/admin/login")

      _ ->
        passkey_failed(conn, "passwordless")
    end
  end

  def passkey(conn, _params), do: passkey_failed(conn, "passwordless")

  defp passkey_login(conn, "second_factor", bytes, issued_at, result, _params, meta) do
    with {user, :pending} <- UserAuth.pending_login(conn),
         nil <- Throttle.locked_until(user),
         challenge = Passkeys.restore_authentication_challenge(user, bytes, issued_at),
         {:ok, _user_id, _passkey} <- Passkeys.authenticate(user, result, challenge) do
      UserAuth.complete_pending_login(conn, user, :passkey)
    else
      nil -> UserAuth.abandon_pending_login(conn, expired_message())
      %DateTime{} = until -> UserAuth.abandon_pending_login(conn, too_many_message(minutes_until(until)))
      {:error, _reason} -> wrong_passkey(conn, meta)
    end
  end

  # Rate limited per address; a failure here does not name an account to count against.
  defp passkey_login(conn, "passwordless", bytes, issued_at, result, params, _meta) do
    challenge = Passkeys.restore_authentication_challenge(:discoverable, bytes, issued_at)

    with {:ok, user_id, _passkey} <- Passkeys.authenticate(:any, result, challenge),
         {:ok, user} <- Users.get_user(%{matches: %{id: user_id, active: true}}),
         nil <- Throttle.locked_until(user) do
      UserAuth.log_in_user(conn, user, %{"remember_me" => params["remember_me"]}, :passkey)
    else
      %DateTime{} = until -> too_many(conn, nil, minutes_until(until))
      _ -> passkey_failed(conn, "passwordless")
    end
  end

  defp wrong_passkey(conn, meta) do
    case UserAuth.pending_login(conn) do
      {user, :pending} ->
        case Throttle.failed(user, :two_factor, meta) do
          :ok -> passkey_failed(conn, "second_factor")
          {:locked, until} -> UserAuth.abandon_pending_login(conn, too_many_message(minutes_until(until)))
        end

      _ ->
        UserAuth.abandon_pending_login(conn, expired_message())
    end
  end

  defp passkey_failed(conn, mode) do
    conn
    |> put_flash(:error, gettext("That passkey did not work. Try again, or use another way to log in."))
    |> redirect(to: if(mode == "second_factor", do: "/admin/login/two-factor", else: "/admin/login"))
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, gettext("Logged out successfully."))
    |> UserAuth.log_out_user()
  end

  defp invalid(conn, email) do
    conn
    |> put_flash(:error, gettext("Invalid email or password"))
    |> put_flash(:email, String.slice(email || "", 0, 160))
    |> redirect(to: "/admin/login")
  end

  defp too_many(conn, email, minutes) do
    conn
    |> put_flash(:error, too_many_message(minutes))
    |> put_flash(:email, String.slice(email || "", 0, 160))
    |> redirect(to: "/admin/login")
  end

  defp too_many_message(minutes) do
    ngettext(
      "Too many attempts. Try again in a minute.",
      "Too many attempts. Try again in %{count} minutes.",
      minutes
    )
  end

  defp expired_message, do: gettext("Your login took too long. Log in again.")

  defp minutes_until(until), do: max(div(DateTime.diff(until, DateTime.utc_now()), 60) + 1, 1)
end

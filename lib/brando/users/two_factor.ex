defmodule Brando.Users.TwoFactor do
  @moduledoc """
  Two-factor authentication for admin users: a time-based one-time password
  (TOTP) from an authenticator app, with one-time recovery codes for when the
  app is lost.

  ## Turning it on

  `new_secret/0` makes a secret, which the user adds to their app by
  scanning `qr_code_svg/1` of `otpauth_uri/2`, or typing `display_secret/1`.
  `enable/4` turns two-factor authentication on once they give a code the
  app shows for it, and returns ten recovery codes, shown once.

  ## Codes

  A code is six digits, for a 30-second time step; one from the step before
  or after is accepted too, for clocks that are a little off. A code works
  once: the step of the last accepted code is stored, and a code for that
  step or an earlier one is refused (`verify/3`).

  A recovery code also works once, in place of a code from the app. Only a
  keyed hash of it is stored (`Brando.Crypto.hmac/2`).

  ## Storage

  The secret is encrypted at rest with `Brando.Crypto`, bound to the user,
  in `Brando.Users.Security`.

  ## Who must use it

  `required?/1` reads the installation's `Brando.Users.SecurityPolicy`. A
  user it applies to without two-factor authentication sets it up at their
  next sign-in, and any session they have ends (`must_enroll?/1`).
  """

  import Ecto.Query

  require Logger

  alias Brando.Repo
  alias Brando.Users
  alias Brando.Users.Passkeys
  alias Brando.Users.RecoveryCode
  alias Brando.Users.Security
  alias Brando.Users.SecurityLog
  alias Brando.Users.SecurityPolicy
  alias Brando.Users.Throttle

  @period 30
  @recovery_code_count 10
  @recovery_alphabet ~c"abcdefghijkmnpqrstuvwxyz23456789"

  ## State

  @doc "`user`'s security row, or an empty one."
  @spec security(map()) :: Security.t()
  def security(%{id: user_id}) do
    Repo.get_by(Security, user_id: user_id) || %Security{user_id: user_id}
  end

  @doc """
  Whether `user` has a second factor: codes from an authenticator app, or a
  passkey (`Brando.Users.Passkeys`).
  """
  @spec enabled?(map()) :: boolean()
  def enabled?(user), do: totp_enabled?(user) or Passkeys.any?(user)

  @doc "Whether `user` has turned on codes from an authenticator app."
  @spec totp_enabled?(map()) :: boolean()
  def totp_enabled?(%{id: user_id}) do
    Repo.repo().exists?(from s in Security, where: s.user_id == ^user_id and not is_nil(s.totp_enabled_at))
  end

  @doc "How many of `user`'s recovery codes are left unused."
  @spec recovery_codes_left(map()) :: non_neg_integer()
  def recovery_codes_left(%{id: user_id}) do
    Repo.aggregate(from(c in RecoveryCode, where: c.user_id == ^user_id and is_nil(c.used_at)), :count)
  end

  ## Setting up

  @doc "A new random secret: 20 bytes, as RFC 4226 suggests."
  @spec new_secret() :: binary()
  def new_secret, do: NimbleTOTP.secret()

  @doc """
  The `otpauth://` URI an authenticator app reads from the QR code: the
  application's name as the issuer, and the user's email.
  """
  @spec otpauth_uri(map(), binary()) :: String.t()
  def otpauth_uri(user, secret) do
    issuer = to_string(Brando.config(:app_name) || "Brando")
    NimbleTOTP.otpauth_uri("#{issuer}:#{user.email}", secret, issuer: issuer)
  end

  @doc """
  A QR code of `uri` as an inline SVG element, which scales with its
  container. It has no quiet zone of its own: put it on a light ground with
  some padding.
  """
  @spec qr_code_svg(String.t()) :: String.t()
  def qr_code_svg(uri) do
    uri
    |> EQRCode.encode(:m)
    |> EQRCode.svg(viewbox: true, background_color: :transparent)
    |> String.replace(~r/\A<\?xml[^>]*>\s*/, "")
  end

  @doc "The secret as the app's manual entry wants it: Base32, in groups of four."
  @spec display_secret(binary()) :: String.t()
  def display_secret(secret) do
    secret
    |> Base.encode32(padding: false)
    |> String.graphemes()
    |> Enum.chunk_every(4)
    |> Enum.map_join(" ", &Enum.join/1)
  end

  @doc """
  Turns two-factor authentication on for `user` with `secret`, once `code`
  is one the app shows for it. It does not replace a secret already in use:
  to move to a new phone, the user turns it off (which asks for their
  password or a code) and on again.

  A session alone is not enough: `opts[:proof]` must be the user's password
  or a current code from a factor they already have (see `confirm/3`; a
  wrong one counts towards the lockout), or `{:signed_in_now, pending_id}`
  from the setup screen of a sign-in whose password was right a moment ago. Otherwise a
  stolen session cookie could add the thief's app, and log the owner out.
  `{:signed_in_now, pending_id}` is accepted only while the waiting sign-in
  with the token row `pending_id` is still valid for the user
  (`Brando.Users.pending_login_valid?/2`) and they have no second factor:
  a password reset ends it.

  Logs the user out of their other sessions, keeping the token row
  `opts[:keep_id]`, and emails the user. Records the change, with
  `opts[:meta]`.

  Returns `{:ok, recovery_codes}` — shown once, then only hashes are kept —
  or `{:error, reason}`: `:invalid_code`, `:already_enabled`,
  `:invalid_proof` or `:locked`.
  """
  @spec enable(map(), binary(), String.t(), keyword()) :: {:ok, [String.t()]} | {:error, atom()}
  def enable(%{id: user_id} = user, secret, code, opts \\ []) do
    with :ok <- check(not totp_enabled?(user), :already_enabled),
         step when is_integer(step) <- matching_step(secret, normalize_code(code)) || {:error, :invalid_code},
         :ok <- check_proof(user, opts[:proof], opts[:meta]) do
      do_enable(user_id, user, secret, step, opts)
    end
  end

  # The setup screen of a sign-in: only while that sign-in (its token row)
  # still waits, and the user has no second factor yet
  defp check_proof(user, {:signed_in_now, pending_id}, _meta) do
    if Users.pending_login_valid?(pending_id, user) and not enabled?(user),
      do: :ok,
      else: {:error, :invalid_proof}
  end

  defp check_proof(user, proof, meta), do: confirm(user, proof, meta)

  defp do_enable(user_id, user, secret, step, opts) do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    encrypted = Brando.Crypto.encrypt(secret, encryption_context(user))

    {:ok, codes} =
      Repo.transaction(fn ->
        Repo.insert!(
          %Security{user_id: user_id, totp_secret: encrypted, totp_enabled_at: now, totp_last_step: step},
          on_conflict: [
            set: [totp_secret: encrypted, totp_enabled_at: now, totp_last_step: step, updated_at: DateTime.to_naive(now)]
          ],
          conflict_target: :user_id
        )

        replace_recovery_codes(user)
      end)

    Users.revoke_sessions(user, except_id: opts[:keep_id])
    SecurityLog.record(:two_factor_enabled, user, meta: opts[:meta])
    Users.notify_security(user, :two_factor_enabled)
    {:ok, codes}
  end

  ## Checking a code

  @doc """
  Checks a code `user` gave at sign-in: six digits from their app, or one of
  their recovery codes, which is then used up.

  Returns `{:ok, :totp}`, `{:ok, :recovery_code}`, `{:error, :invalid}`, or
  `{:error, :unreadable}` when the stored secret cannot be decrypted (the
  encryption secret changed), which is the site's fault, not a wrong guess.
  It does not count failures; the caller does, with `Brando.Users.Throttle`.
  """
  @spec verify(map(), String.t() | nil) :: {:ok, :totp | :recovery_code} | {:error, :invalid | :unreadable}
  def verify(user, code) when is_binary(code) do
    normalized = normalize_code(code)

    cond do
      totp_shaped?(normalized) -> totp_result(check_totp(user, normalized))
      use_recovery_code(user, normalized) -> {:ok, :recovery_code}
      true -> {:error, :invalid}
    end
  end

  def verify(_user, _code), do: {:error, :invalid}

  defp totp_result(:ok), do: {:ok, :totp}
  defp totp_result(error), do: {:error, error}

  @doc """
  Whether `code` is the app's code for `user` now, and not one already used:
  accepting it stores its time step, in the same statement that checks the
  last one, so a code cannot be used twice even by two requests at once.
  """
  @spec valid_totp?(map(), String.t()) :: boolean()
  def valid_totp?(user, code), do: check_totp(user, code) == :ok

  # `:ok`, `:invalid`, or `:unreadable` when the stored secret does not
  # decrypt: logged, since it means the encryption secret changed.
  defp check_totp(%{id: user_id} = user, code) do
    with %Security{totp_secret: encrypted, totp_enabled_at: %DateTime{}} <- security(user),
         {:ok, secret} <- decrypt_secret(user, encrypted),
         step when is_integer(step) <- matching_step(secret, normalize_code(code)) do
      {count, _} =
        from(s in Security,
          where: s.user_id == ^user_id and not is_nil(s.totp_enabled_at),
          where: is_nil(s.totp_last_step) or s.totp_last_step < ^step
        )
        |> Repo.update_all(set: [totp_last_step: step])

      if count == 1, do: :ok, else: :invalid
    else
      :unreadable -> :unreadable
      _ -> :invalid
    end
  end

  defp decrypt_secret(user, encrypted) do
    case Brando.Crypto.decrypt(encrypted, encryption_context(user)) do
      {:ok, secret} ->
        {:ok, secret}

      :error ->
        Logger.error(
          "[Brando.Users.TwoFactor] The two-factor secret of user ##{user.id} cannot be decrypted. " <>
            "Has the encryption secret (Brando.Crypto, or the endpoint's secret_key_base) changed? " <>
            "The user can log in with a recovery code, or an administrator can reset two-factor authentication."
        )

        :unreadable
    end
  end

  # The time step `code` is the app's code for: now, or one step either side
  defp matching_step(secret, code) when byte_size(code) == 6 do
    current = div(System.os_time(:second), @period)

    Enum.find([current, current - 1, current + 1], fn step ->
      Plug.Crypto.secure_compare(NimbleTOTP.verification_code(secret, time: step * @period), code)
    end)
  end

  defp matching_step(_secret, _code), do: nil

  defp totp_shaped?(code), do: byte_size(code) == 6 and code =~ ~r/^\d{6}$/

  defp normalize_code(code) when is_binary(code),
    do: code |> String.downcase() |> String.replace(~r/[\s-]/u, "")

  defp normalize_code(_), do: ""

  @doc "The app's code for `secret` now. For tests and fixtures."
  @spec current_code(binary()) :: String.t()
  def current_code(secret), do: NimbleTOTP.verification_code(secret)

  ## Recovery codes

  @doc """
  Uses up one of `user`'s recovery codes, if `code` is one that is unused.
  The check and the use are one statement.
  """
  @spec use_recovery_code(map(), String.t()) :: boolean()
  def use_recovery_code(%{id: user_id} = user, code) do
    hashed = hash_recovery_code(user, normalize_code(code))
    now = DateTime.truncate(DateTime.utc_now(), :second)

    {count, _} =
      from(c in RecoveryCode, where: c.user_id == ^user_id and c.hashed_code == ^hashed and is_nil(c.used_at))
      |> Repo.update_all(set: [used_at: now])

    count == 1
  end

  @doc """
  Replaces `user`'s recovery codes with new ones, once they confirm it is
  them (`confirm/3`). Returns `{:ok, codes}` or `{:error, :invalid_proof}`.
  """
  @spec regenerate_recovery_codes(map(), String.t(), keyword()) :: {:ok, [String.t()]} | {:error, atom()}
  def regenerate_recovery_codes(user, proof, opts \\ []) do
    with :ok <- check_enabled(user),
         :ok <- confirm(user, proof, opts[:meta]) do
      {:ok, codes} = Repo.transaction(fn -> replace_recovery_codes(user) end)
      SecurityLog.record(:recovery_codes_created, user, meta: opts[:meta])
      {:ok, codes}
    end
  end

  @doc """
  Makes `user` a new set of recovery codes, replacing any they had, and
  returns them, for showing once. For a first second factor; making new ones
  later asks for proof, with `regenerate_recovery_codes/3`.
  """
  @spec create_recovery_codes(map()) :: [String.t()]
  def create_recovery_codes(user) do
    {:ok, codes} = Repo.transaction(fn -> replace_recovery_codes(user) end)
    codes
  end

  @doc "Deletes `user`'s recovery codes, once they have no second factor left."
  @spec delete_recovery_codes(map()) :: :ok
  def delete_recovery_codes(%{id: user_id}) do
    Repo.delete_all(from c in RecoveryCode, where: c.user_id == ^user_id)
    :ok
  end

  defp replace_recovery_codes(%{id: user_id} = user) do
    Repo.delete_all(from c in RecoveryCode, where: c.user_id == ^user_id)
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    codes = Enum.map(1..@recovery_code_count, fn _ -> new_recovery_code() end)

    Repo.insert_all(
      RecoveryCode,
      Enum.map(codes, &%{user_id: user_id, hashed_code: hash_recovery_code(user, normalize_code(&1)), inserted_at: now})
    )

    codes
  end

  @doc false
  # Ten characters from an alphabet without look-alikes (no l, o, 0, 1):
  # 50 bits, shown as xxxxx-xxxxx. From the operating system's secure random
  # bytes, never `:rand`.
  def new_recovery_code do
    {first, second} = @recovery_alphabet |> random_chars(10) |> Enum.split(5)
    "#{first}-#{second}"
  end

  # Rejection sampling: a byte is used only below the largest multiple of the
  # alphabet's size, so every character is equally likely. (With 32
  # characters every byte is used; the rule keeps it so for another alphabet.)
  defp random_chars(alphabet, count, acc \\ [])
  defp random_chars(_alphabet, 0, acc), do: acc

  defp random_chars(alphabet, count, acc) do
    size = length(alphabet)
    limit = 256 - rem(256, size)

    case :crypto.strong_rand_bytes(1) do
      <<byte>> when byte < limit -> random_chars(alphabet, count - 1, [Enum.at(alphabet, rem(byte, size)) | acc])
      _ -> random_chars(alphabet, count, acc)
    end
  end

  defp hash_recovery_code(%{id: user_id}, normalized),
    do: Brando.Crypto.hmac("#{user_id}:#{normalized}", "users.recovery_code")

  ## Turning it off

  @doc """
  Turns codes from an authenticator app off for `user`, once they confirm
  it is them (`confirm/3`). With no passkey left, the recovery codes go too.
  Returns `:ok`, or `{:error, reason}`: `:invalid_proof`, `:locked`,
  `:not_enabled`, or `:required` when the sign-in policy says they must use
  two-factor authentication and they have no passkey.
  """
  @spec disable(map(), String.t(), keyword()) :: :ok | {:error, atom()}
  def disable(user, proof, opts \\ []) do
    with :ok <- check(totp_enabled?(user), :not_enabled),
         :ok <- check(Passkeys.any?(user) or not required?(user), :required),
         :ok <- confirm(user, proof, opts[:meta]) do
      clear(user)
      SecurityLog.record(:two_factor_disabled, user, meta: opts[:meta])
      Users.notify_security(user, :two_factor_disabled)
      :ok
    end
  end

  @doc """
  Turns two-factor authentication off for the user `user_id` on behalf of
  `actor`, for someone who lost their app, passkeys and recovery codes: the
  app's secret, every passkey and the recovery codes go. Also ends a
  lockout, and logs the user out everywhere: they sign in with their
  password, and set two-factor authentication up again if they must.

  Allowed to whoever may reset the user's password
  (`Brando.Trait.ProtectPassword.allowed?/2`), but not for their own account.
  Returns `{:ok, user}` or `{:error, :forbidden | :not_found}`.
  """
  @spec reset(integer() | String.t(), map(), keyword()) :: {:ok, map()} | {:error, atom()}
  def reset(user_id, actor, opts \\ []) do
    with {:ok, user} <- fetch_user(user_id),
         :ok <- check(user.id != actor.id, :forbidden),
         :ok <- check(Brando.Trait.ProtectPassword.allowed?(actor, user), :forbidden) do
      clear(user)
      Passkeys.delete_all(user)
      delete_recovery_codes(user)
      Throttle.clear(user)
      Users.revoke_sessions(user)
      SecurityLog.record(:two_factor_reset, user, actor: actor, meta: opts[:meta])
      Users.notify_security(user, :two_factor_reset)
      {:ok, user}
    end
  end

  defp fetch_user(user_id) do
    case Users.get_user(user_id) do
      {:ok, user} -> {:ok, user}
      _ -> {:error, :not_found}
    end
  end

  defp clear(%{id: user_id} = user) do
    Repo.transaction(fn ->
      from(s in Security, where: s.user_id == ^user_id)
      |> Repo.update_all(set: [totp_secret: nil, totp_enabled_at: nil, totp_last_step: nil])

      unless Passkeys.any?(user), do: delete_recovery_codes(user)
    end)
  end

  defp check_enabled(user), do: check(enabled?(user), :not_enabled)

  defp check(true, _reason), do: :ok
  defp check(_, reason), do: {:error, reason}

  ## Confirming it is the user

  @doc """
  Checks that the signed-in `user` is who they say before a change to their
  security: `proof` is their password, or a current code from their app
  (not a recovery code). A wrong one counts towards the lockout.

  Returns `:ok`, or `{:error, reason}`: `:invalid_proof`, `:locked`, or
  `:unreadable` for a code when the stored secret cannot be decrypted, which
  does not count as a failure.
  """
  @spec confirm(map(), String.t() | nil, SecurityLog.meta() | nil) ::
          :ok | {:error, :invalid_proof | :locked | :unreadable}
  def confirm(user, proof, meta \\ nil) do
    if Throttle.locked_until(user) do
      {:error, :locked}
    else
      case is_binary(proof) && proof_result(user, proof) do
        :ok -> :ok
        :unreadable -> {:error, :unreadable}
        _ -> count_failure(user, meta)
      end
    end
  end

  defp count_failure(user, meta) do
    case Throttle.failed(user, :confirm, meta || %{}) do
      {:locked, _until} -> {:error, :locked}
      :ok -> {:error, :invalid_proof}
    end
  end

  defp proof_result(user, proof) do
    code = normalize_code(proof)
    totp = if totp_shaped?(code), do: check_totp(user, code), else: :invalid

    cond do
      totp == :ok -> :ok
      password_valid?(user, proof) -> :ok
      true -> totp
    end
  end

  defp password_valid?(%{id: user_id}, password) do
    case Repo.one(from u in Brando.Users.User, where: u.id == ^user_id, select: u.password) do
      hash when is_binary(hash) -> Bcrypt.verify_pass(password, hash)
      _ -> Bcrypt.no_user_verify()
    end
  end

  defp encryption_context(%{id: user_id}), do: "users.totp_secret:#{user_id}"

  ## Who must use it

  @doc """
  Whether the sign-in policy says `user` must use two-factor authentication:
  everyone, or the roles — with groups authorization, the groups — it names.
  """
  @spec required?(map()) :: boolean()
  def required?(user), do: SecurityPolicy.applies?(SecurityPolicy.get(), user)

  @doc """
  Whether `user` must set two-factor authentication up before they can use
  the admin: the policy requires it and they have not.
  """
  @spec must_enroll?(map()) :: boolean()
  def must_enroll?(user), do: required?(user) and not enabled?(user)
end

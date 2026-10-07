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

  alias Brando.Repo
  alias Brando.Users
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

  @doc "Whether `user` has turned two-factor authentication on."
  @spec enabled?(map()) :: boolean()
  def enabled?(%{id: user_id}) do
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

  Logs the user out of their other sessions, keeping the one with
  `opts[:keep_token]`. Records the change, with `opts[:meta]`.

  Returns `{:ok, recovery_codes}` — shown once, then only hashes are kept —
  or `{:error, :invalid_code}` or `{:error, :already_enabled}`.
  """
  @spec enable(map(), binary(), String.t(), keyword()) :: {:ok, [String.t()]} | {:error, :invalid_code | :already_enabled}
  def enable(%{id: user_id} = user, secret, code, opts \\ []) do
    cond do
      enabled?(user) -> {:error, :already_enabled}
      step = matching_step(secret, normalize_code(code)) -> do_enable(user_id, user, secret, step, opts)
      true -> {:error, :invalid_code}
    end
  end

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

    Users.revoke_sessions(user, except: opts[:keep_token])
    SecurityLog.record(:two_factor_enabled, user, meta: opts[:meta])
    {:ok, codes}
  end

  ## Checking a code

  @doc """
  Checks a code `user` gave at sign-in: six digits from their app, or one of
  their recovery codes, which is then used up.

  Returns `{:ok, :totp}`, `{:ok, :recovery_code}` or `{:error, :invalid}`.
  It does not count failures; the caller does, with `Brando.Users.Throttle`.
  """
  @spec verify(map(), String.t() | nil) :: {:ok, :totp | :recovery_code} | {:error, :invalid}
  def verify(user, code) when is_binary(code) do
    normalized = normalize_code(code)

    cond do
      totp_shaped?(normalized) and valid_totp?(user, normalized) -> {:ok, :totp}
      not totp_shaped?(normalized) and use_recovery_code(user, normalized) -> {:ok, :recovery_code}
      true -> {:error, :invalid}
    end
  end

  def verify(_user, _code), do: {:error, :invalid}

  @doc """
  Whether `code` is the app's code for `user` now, and not one already used:
  accepting it stores its time step, in the same statement that checks the
  last one, so a code cannot be used twice even by two requests at once.
  """
  @spec valid_totp?(map(), String.t()) :: boolean()
  def valid_totp?(%{id: user_id} = user, code) do
    with %Security{totp_secret: encrypted, totp_enabled_at: %DateTime{}} <- security(user),
         {:ok, secret} <- Brando.Crypto.decrypt(encrypted, encryption_context(user)),
         step when is_integer(step) <- matching_step(secret, normalize_code(code)) do
      {count, _} =
        from(s in Security,
          where: s.user_id == ^user_id and not is_nil(s.totp_enabled_at),
          where: is_nil(s.totp_last_step) or s.totp_last_step < ^step
        )
        |> Repo.update_all(set: [totp_last_step: step])

      count == 1
    else
      _ -> false
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

  # Ten characters from an alphabet without look-alikes (no l, o, 0, 1):
  # 50 bits, shown as xxxxx-xxxxx
  defp new_recovery_code do
    chars = for _ <- 1..10, do: Enum.random(@recovery_alphabet)
    {first, second} = Enum.split(chars, 5)
    "#{first}-#{second}"
  end

  defp hash_recovery_code(%{id: user_id}, normalized),
    do: Brando.Crypto.hmac("#{user_id}:#{normalized}", "users.recovery_code")

  ## Turning it off

  @doc """
  Turns two-factor authentication off for `user`, once they confirm it is
  them (`confirm/3`). Returns `:ok`, or `{:error, reason}`: `:invalid_proof`,
  `:locked`, `:not_enabled`, or `:required` when the sign-in policy says
  they must use it.
  """
  @spec disable(map(), String.t(), keyword()) :: :ok | {:error, atom()}
  def disable(user, proof, opts \\ []) do
    with :ok <- check_enabled(user),
         :ok <- check(not required?(user), :required),
         :ok <- confirm(user, proof, opts[:meta]) do
      clear(user)
      SecurityLog.record(:two_factor_disabled, user, meta: opts[:meta])
      :ok
    end
  end

  @doc """
  Turns two-factor authentication off for the user `user_id` on behalf of
  `actor`, for someone who lost their app and their recovery codes. Also
  ends a lockout, and logs the user out everywhere: they sign in with their
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
      Throttle.clear(user)
      Users.revoke_sessions(user)
      SecurityLog.record(:two_factor_reset, user, actor: actor, meta: opts[:meta])
      {:ok, user}
    end
  end

  defp fetch_user(user_id) do
    case Users.get_user(user_id) do
      {:ok, user} -> {:ok, user}
      _ -> {:error, :not_found}
    end
  end

  defp clear(%{id: user_id}) do
    Repo.transaction(fn ->
      from(s in Security, where: s.user_id == ^user_id)
      |> Repo.update_all(set: [totp_secret: nil, totp_enabled_at: nil, totp_last_step: nil])

      Repo.delete_all(from c in RecoveryCode, where: c.user_id == ^user_id)
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

  Returns `:ok`, or `{:error, :invalid_proof}` or `{:error, :locked}`.
  """
  @spec confirm(map(), String.t() | nil, SecurityLog.meta() | nil) :: :ok | {:error, :invalid_proof | :locked}
  def confirm(user, proof, meta \\ nil) do
    cond do
      Throttle.locked_until(user) ->
        {:error, :locked}

      is_binary(proof) and proof_valid?(user, proof) ->
        :ok

      true ->
        case Throttle.failed(user, :confirm, meta || %{}) do
          {:locked, _until} -> {:error, :locked}
          :ok -> {:error, :invalid_proof}
        end
    end
  end

  defp proof_valid?(user, proof) do
    code = normalize_code(proof)

    (totp_shaped?(code) and valid_totp?(user, code)) or password_valid?(user, proof)
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

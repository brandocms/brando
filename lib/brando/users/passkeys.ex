defmodule Brando.Users.Passkeys do
  @moduledoc """
  Passkeys (WebAuthn credentials) for admin users, checked with `Wax`.

  A passkey is a second factor, in place of a code from an authenticator
  app, and satisfies a sign-in policy that requires two-factor
  authentication. Once a user has one, they can also log in with it alone:
  the passkey is something they have, and the device asks for their PIN,
  fingerprint or face before it signs (user verification is required for
  that).

  ## Origin

  The relying party is the admin's own address: the origin is the
  endpoint's URL and the RP ID its host, unless the application sets them:

      config :brando, Brando.Users.Passkeys,
        origin: "https://admin.example.com",
        rp_id: "example.com"

  A passkey only works on the RP ID it was made for, so it stays the same
  for as long as the passkeys should work.

  ## Challenges

  Every ceremony starts with a fresh random challenge from
  `registration_challenge/1` or `authentication_challenge/2`, which the
  caller keeps on the server side (a LiveView's assigns, or the signed
  session for the login screens) and passes back with the browser's answer.
  A challenge is valid for five minutes and answers once: its hash is kept
  as a `users_tokens` row once used, so an old copy of the session cookie
  cannot bring it back.
  """

  import Ecto.Query

  alias Brando.Repo
  alias Brando.Users.Passkey
  alias Brando.Users.RecoveryCode
  alias Brando.Users.SecurityLog
  alias Brando.Users.TwoFactor
  alias Brando.Users.UserToken

  @timeout 300
  @algorithms [-7, -257]

  @type browser_result :: %{optional(String.t()) => String.t()}

  ## Reading

  @doc "`user`'s passkeys, oldest first."
  @spec list(map()) :: [Passkey.t()]
  def list(%{id: user_id}) do
    Repo.all(from p in Passkey, where: p.user_id == ^user_id, order_by: [asc: p.inserted_at, asc: p.id])
  end

  @doc "Whether `user` has a passkey."
  @spec any?(map()) :: boolean()
  def any?(%{id: user_id}), do: Repo.repo().exists?(from p in Passkey, where: p.user_id == ^user_id)

  ## Relying party

  @doc "The origin and RP ID passkeys are made for and checked against."
  @spec relying_party() :: keyword()
  def relying_party do
    config = Brando.config(__MODULE__) || []
    origin = config[:origin] || String.trim_trailing(Brando.endpoint().url(), "/")
    [origin: origin, rp_id: config[:rp_id] || URI.parse(origin).host]
  end

  # An opaque handle for the user in the authenticator, which is not their id
  # or email: the authenticator may show it to whoever holds the device.
  defp user_handle(%{id: user_id}), do: Brando.Crypto.hmac("#{user_id}", "users.passkey_handle")

  ## Registering

  defmodule Registration do
    @moduledoc """
    A passkey registration under way for `user_id`, made by
    `Brando.Users.Passkeys.start_registration/3` once the user proved it is
    them. Its challenge does not show when inspected.
    """
    @derive {Inspect, only: [:user_id]}
    @enforce_keys [:user_id, :challenge]
    defstruct [:user_id, :challenge, :pending_id]

    @type t :: %__MODULE__{user_id: integer(), challenge: Wax.Challenge.t(), pending_id: integer() | nil}
  end

  @doc """
  Starts adding a passkey for `user`, once they prove it is them: `proof` is
  their password or a current code from their app (`TwoFactor.confirm/3`;
  a wrong one counts towards the lockout), or `{:signed_in_now, pending_id}`
  on the setup screen of a sign-in whose password was right a moment ago —
  accepted only while that sign-in (its token row `pending_id`) still waits
  for this user and they have no second factor, checked again by
  `register/5`. A passkey logs in on its own and outlasts a password reset,
  so a session alone must not be enough to add one.

  Returns `{:ok, registration, options}` — the `publicKey` options for
  `navigator.credentials.create/1` — or `{:error, :invalid_proof | :locked}`.
  """
  @spec start_registration(map(), String.t() | {:signed_in_now, integer()} | nil, keyword()) ::
          {:ok, Registration.t(), map()} | {:error, atom()}
  def start_registration(user, proof, opts \\ []) do
    with :ok <- check_proof(user, proof, opts[:meta]) do
      {challenge, options} = registration_challenge(user)

      pending_id =
        case proof do
          {:signed_in_now, id} -> id
          _ -> nil
        end

      {:ok, %Registration{user_id: user.id, challenge: challenge, pending_id: pending_id}, options}
    end
  end

  defp check_proof(user, {:signed_in_now, pending_id}, _meta), do: check_pending(user, pending_id)

  defp check_proof(user, proof, meta) do
    case TwoFactor.confirm(user, proof, meta) do
      :ok -> :ok
      {:error, :unreadable} -> {:error, :invalid_proof}
      error -> error
    end
  end

  # A challenge for registering a new passkey for `user`, and the `publicKey`
  # options for `navigator.credentials.create/1`, with binaries
  # Base64url-encoded. The user's own passkeys are excluded, so a device is
  # not added twice.
  defp registration_challenge(user) do
    challenge =
      Wax.new_registration_challenge(
        relying_party() ++ [attestation: "none", user_verification: "preferred", timeout: @timeout]
      )

    options = %{
      challenge: encode(challenge.bytes),
      rp: %{id: challenge.rp_id, name: to_string(Brando.config(:app_name) || "Brando")},
      user: %{id: encode(user_handle(user)), name: user.email, displayName: user.name || user.email},
      pubKeyCredParams: Enum.map(@algorithms, &%{type: "public-key", alg: &1}),
      timeout: @timeout * 1000,
      attestation: "none",
      authenticatorSelection: %{residentKey: "preferred", requireResidentKey: false, userVerification: "preferred"},
      excludeCredentials: Enum.map(list(user), &%{type: "public-key", id: encode(&1.credential_id)})
    }

    {challenge, options}
  end

  @doc """
  Registers the passkey the browser made for `registration` (see
  `start_registration/3`) as `user`'s, under `name`. `result` holds the
  browser's `attestation_object` and `client_data_json`, Base64url-encoded.
  The user is emailed.

  The first second factor a user adds — no app, no other passkey — also
  makes their recovery codes, and logs out their other sessions (all but the
  token row `opts[:keep_id]`), as turning on the app does.

  Returns `{:ok, passkey, recovery_codes}`, with the codes only when they
  were made now (otherwise nil), or `{:error, reason}`.
  """
  @spec register(map(), String.t() | nil, browser_result(), Registration.t(), keyword()) ::
          {:ok, Passkey.t(), [String.t()] | nil} | {:error, atom()}
  def register(%{id: user_id} = user, name, result, %Registration{user_id: user_id} = registration, opts \\ []) do
    first? = not TwoFactor.enabled?(user)
    challenge = registration.challenge

    with :ok <- recheck_pending(user, registration),
         {:ok, attestation_object} <- decode(result["attestation_object"]),
         {:ok, client_data_json} <- decode(result["client_data_json"]),
         {:ok, {auth_data, _attestation}} <- wax(Wax.register(attestation_object, client_data_json, challenge)),
         %{credential_id: credential_id, credential_public_key: cose_key} <- auth_data.attested_credential_data,
         {:ok, passkey} <- insert(user, name, credential_id, cose_key, auth_data) do
      codes = if first?, do: first_factor_added(user, opts), else: nil
      SecurityLog.record(:passkey_added, user, meta: opts[:meta], details: %{"name" => passkey.name})
      Brando.Users.notify_security(user, :passkey_added, %{name: passkey.name})
      {:ok, passkey, codes}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid}
    end
  end

  # A registration a waiting sign-in vouched for: only while it still waits
  defp recheck_pending(_user, %Registration{pending_id: nil}), do: :ok
  defp recheck_pending(user, %Registration{pending_id: id}), do: check_pending(user, id)

  defp check_pending(user, pending_id) do
    if Brando.Users.pending_login_valid?(pending_id, user) and not TwoFactor.enabled?(user),
      do: :ok,
      else: {:error, :invalid_proof}
  end

  defp insert(%{id: user_id}, name, credential_id, cose_key, auth_data) do
    name = name |> to_string() |> String.trim() |> String.slice(0, 60)

    %Passkey{
      user_id: user_id,
      name: if(name == "", do: default_name(), else: name),
      credential_id: credential_id,
      cose_key: :erlang.term_to_binary(cose_key),
      sign_count: auth_data.sign_count,
      aaguid: Wax.AuthenticatorData.get_aaguid(auth_data)
    }
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.unique_constraint(:credential_id)
    |> Repo.insert()
    |> case do
      {:ok, passkey} -> {:ok, passkey}
      {:error, _changeset} -> {:error, :already_registered}
    end
  end

  defp default_name, do: "Passkey"

  defp first_factor_added(user, opts) do
    Brando.Users.revoke_sessions(user, except_id: opts[:keep_id])

    if Repo.repo().exists?(from c in RecoveryCode, where: c.user_id == ^user.id and is_nil(c.used_at)),
      do: nil,
      else: TwoFactor.create_recovery_codes(user)
  end

  ## Authenticating

  @doc """
  A challenge for confirming with a passkey, and the `publicKey` options for
  `navigator.credentials.get/1`. With a user, it allows only their passkeys;
  with `:discoverable`, the browser offers whichever passkey for this site
  the device holds, and user verification is required, since the passkey
  is then the only factor.
  """
  @spec authentication_challenge(map() | :discoverable, keyword()) :: {Wax.Challenge.t(), map()}
  def authentication_challenge(user_or_discoverable, opts \\ [])

  def authentication_challenge(:discoverable, opts) do
    challenge = new_authentication_challenge([], "required", opts)
    {challenge, request_options(challenge, [])}
  end

  def authentication_challenge(user, opts) do
    passkeys = list(user)
    allow = Enum.map(passkeys, &{&1.credential_id, :erlang.binary_to_term(&1.cose_key, [:safe])})
    challenge = new_authentication_challenge(allow, "preferred", opts)
    {challenge, request_options(challenge, passkeys)}
  end

  defp new_authentication_challenge(allow, user_verification, opts) do
    Wax.new_authentication_challenge(
      relying_party() ++
        [allow_credentials: allow, user_verification: user_verification, timeout: @timeout] ++
        Keyword.take(opts, [:bytes])
    )
  end

  defp request_options(challenge, passkeys) do
    %{
      challenge: encode(challenge.bytes),
      rpId: challenge.rp_id,
      timeout: @timeout * 1000,
      userVerification: challenge.user_verification,
      allowCredentials: Enum.map(passkeys, &%{type: "public-key", id: encode(&1.credential_id)})
    }
  end

  @doc """
  Rebuilds an authentication challenge from what the login screens keep in
  the session: its bytes, when it was issued, and whether it was
  `:discoverable` or for `user`.
  """
  @spec restore_authentication_challenge(map() | :discoverable, binary(), integer()) :: Wax.Challenge.t()
  def restore_authentication_challenge(user_or_discoverable, bytes, issued_at) do
    {challenge, _options} = authentication_challenge(user_or_discoverable, bytes: bytes)
    %{challenge | issued_at: issued_at}
  end

  @doc """
  Checks the browser's answer to `challenge`: the passkey must be one of
  `user`'s (or, with `:any`, anyone's, for logging in with a passkey alone),
  and its signature right. Updates the passkey's counter and last use.

  Returns `{:ok, user_id, passkey}` or `{:error, reason}`. A counter that
  goes backwards, which suggests a copied authenticator, is refused.
  """
  @spec authenticate(map() | :any, browser_result(), Wax.Challenge.t()) ::
          {:ok, integer(), Passkey.t()} | {:error, atom()}
  def authenticate(user_or_any, result, %Wax.Challenge{} = challenge) do
    with {:ok, credential_id} <- decode(result["id"]),
         {:ok, authenticator_data} <- decode(result["authenticator_data"]),
         {:ok, signature} <- decode(result["signature"]),
         {:ok, client_data_json} <- decode(result["client_data_json"]),
         %Passkey{} = passkey <- find(user_or_any, credential_id),
         cose_key = :erlang.binary_to_term(passkey.cose_key, [:safe]),
         {:ok, auth_data} <-
           wax(
             Wax.authenticate(credential_id, authenticator_data, signature, client_data_json, challenge, [
               {credential_id, cose_key}
             ])
           ),
         :ok <- check_counter(passkey, auth_data.sign_count),
         :ok <- use_challenge(passkey.user_id, challenge) do
      now = DateTime.truncate(DateTime.utc_now(), :second)

      {1, _} =
        from(p in Passkey, where: p.id == ^passkey.id)
        |> Repo.update_all(set: [sign_count: auth_data.sign_count, last_used_at: now])

      {:ok, passkey.user_id, %{passkey | sign_count: auth_data.sign_count, last_used_at: now}}
    else
      nil -> {:error, :unknown_passkey}
      {:error, reason} -> {:error, reason}
    end
  end

  # A challenge answers once, on every node: the login screens keep it in the
  # signed cookie session, which an old copy of the cookie would bring back.
  # Its hash is stored as a token, unique per context, until it has expired.
  defp use_challenge(user_id, challenge) do
    hashed = :crypto.hash(:sha256, challenge.bytes)
    expired = NaiveDateTime.add(NaiveDateTime.utc_now(), -2 * @timeout, :second)
    Repo.delete_all(from t in UserToken, where: t.context == "passkey_challenge" and t.inserted_at < ^expired)

    %UserToken{token: hashed, context: "passkey_challenge", user_id: user_id}
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.unique_constraint([:context, :token], name: :users_tokens_context_token_index)
    |> Repo.insert()
    |> case do
      {:ok, _token} -> :ok
      {:error, _changeset} -> {:error, :replayed}
    end
  end

  defp find(:any, credential_id), do: Repo.get_by(Passkey, credential_id: credential_id)
  defp find(%{id: user_id}, credential_id), do: Repo.get_by(Passkey, credential_id: credential_id, user_id: user_id)

  # Synced passkeys always count 0; a counter only means something once it moves.
  defp check_counter(%{sign_count: stored}, new) when stored > 0 and new <= stored, do: {:error, :counter}
  defp check_counter(_passkey, _new), do: :ok

  ## Removing

  @doc """
  Removes `user`'s passkey `passkey_id`. Not the last second factor of a
  user the sign-in policy requires it of. When it was the last second
  factor, the recovery codes go too. Returns `:ok` or `{:error, reason}`.
  """
  @spec delete(map(), integer() | String.t(), keyword()) :: :ok | {:error, :not_found | :required}
  def delete(%{id: user_id} = user, passkey_id, opts \\ []) do
    with %Passkey{} = passkey <- Repo.get_by(Passkey, id: passkey_id, user_id: user_id),
         false <- last_factor?(user) and TwoFactor.required?(user) do
      Repo.delete!(passkey)

      unless TwoFactor.enabled?(user) do
        TwoFactor.delete_recovery_codes(user)
        # Connected tools need two-factor authentication
        Brando.MCP.revoke_user_grants(user, "two_factor_off")
      end

      SecurityLog.record(:passkey_removed, user, meta: opts[:meta], details: %{"name" => passkey.name})
      Brando.Users.notify_security(user, :passkey_removed, %{name: passkey.name})
      :ok
    else
      nil -> {:error, :not_found}
      true -> {:error, :required}
    end
  end

  defp last_factor?(user), do: length(list(user)) == 1 and not TwoFactor.totp_enabled?(user)

  @doc "Removes all of `user`'s passkeys, for an administrator's reset."
  @spec delete_all(map()) :: non_neg_integer()
  def delete_all(%{id: user_id}) do
    {count, _} = Repo.delete_all(from p in Passkey, where: p.user_id == ^user_id)
    count
  end

  ## Encoding

  defp encode(binary), do: Base.url_encode64(binary, padding: false)

  defp decode(text) when is_binary(text) do
    case Base.url_decode64(text, padding: false) do
      {:ok, binary} -> {:ok, binary}
      :error -> {:error, :invalid}
    end
  end

  defp decode(_), do: {:error, :invalid}

  defp wax({:ok, _} = ok), do: ok
  defp wax({:error, _exception}), do: {:error, :invalid}
end

defmodule Brando.Users.PasskeysTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Test.SoftAuthenticator
  alias Brando.Users
  alias Brando.Users.Passkey
  alias Brando.Users.Passkeys
  alias Brando.Users.SecurityEvent
  alias Brando.Users.SecurityPolicy
  alias Brando.Users.TwoFactor
  alias Brando.Users.UserConfig

  defp user(attrs \\ []),
    do: Factory.insert(:random_user, Keyword.merge([role: :editor, config: %UserConfig{}], attrs))

  defp origin, do: Keyword.fetch!(Passkeys.relying_party(), :origin)

  defp register(user, name \\ "Laptop", authenticator \\ SoftAuthenticator.new()) do
    {:ok, challenge, options} = Passkeys.start_registration(user, "admin")
    result = SoftAuthenticator.register(authenticator, options, origin())
    {Passkeys.register(user, name, result, challenge), authenticator}
  end

  defp assert_with(user_or_any, authenticator, opts \\ []) do
    subject = if user_or_any == :any, do: :discoverable, else: user_or_any
    {challenge, options} = Passkeys.authentication_challenge(subject)
    result = SoftAuthenticator.assert(authenticator, options, Keyword.put_new(opts, :origin, origin()))
    Passkeys.authenticate(user_or_any, result, challenge)
  end

  describe "starting to add one" do
    test "a session alone is not enough: it needs the password or a current code" do
      user = user()

      assert {:error, :invalid_proof} = Passkeys.start_registration(user, nil)
      assert {:error, :invalid_proof} = Passkeys.start_registration(user, "not the password")

      assert [%{details: %{"reason" => "confirm"}}, _] =
               Repo.all(from e in SecurityEvent, where: e.user_id == ^user.id and e.action == :login_failed)

      assert {:ok, %Passkeys.Registration{}, _options} = Passkeys.start_registration(user, "admin")
      pending_id = Users.token_id(Users.generate_pending_token(user), "pending_2fa")
      assert {:ok, _registration, _options} = Passkeys.start_registration(user, {:signed_in_now, pending_id})
    end

    # The review's probe: someone with the password holds the required-setup
    # screen open; the owner resets their password, which ends that sign-in
    test "a waiting sign-in vouches only while it lasts, from the start to the registration" do
      user = user()
      pending_id = Users.token_id(Users.generate_pending_token(user), "pending_2fa")
      {:ok, registration, options} = Passkeys.start_registration(user, {:signed_in_now, pending_id})
      result = SoftAuthenticator.register(SoftAuthenticator.new(), options, origin())

      {:ok, _} = Users.reset_user_password(user, %{password: "a new one", password_confirmation: "a new one"})

      assert {:error, :invalid_proof} = Passkeys.register(user, "Thief's laptop", result, registration)
      assert {:error, :invalid_proof} = Passkeys.start_registration(user, {:signed_in_now, pending_id})
      assert Passkeys.list(user) == []
    end

    test "a waiting sign-in does not vouch once the user has a second factor" do
      user = user()
      pending_id = Users.token_id(Users.generate_pending_token(user), "pending_2fa")
      register(user)

      assert {:error, :invalid_proof} = Passkeys.start_registration(user, {:signed_in_now, pending_id})
    end

    test "with an app, a current code proves it is the user" do
      user = user()
      secret = TwoFactor.new_secret()
      {:ok, _codes} = TwoFactor.enable(user, secret, TwoFactor.current_code(secret), proof: "admin")
      Repo.update_all(from(s in Brando.Users.Security, where: s.user_id == ^user.id), set: [totp_last_step: nil])

      assert {:ok, _registration, _options} = Passkeys.start_registration(user, TwoFactor.current_code(secret))
    end

    test "a registration started for one user does not register for another" do
      user = user()
      other = user()
      {:ok, registration, options} = Passkeys.start_registration(user, "admin")
      result = SoftAuthenticator.register(SoftAuthenticator.new(), options, origin())

      assert_raise FunctionClauseError, fn -> Passkeys.register(other, "x", result, registration) end
    end

    test "the challenge does not show when inspected" do
      {:ok, registration, _options} = Passkeys.start_registration(user(), "admin")
      refute inspect(registration) =~ "bytes"
      refute inspect(Brando.Redacted.wrap(registration.challenge)) =~ "bytes"
    end
  end

  describe "registering" do
    test "adds a passkey, and the first second factor makes the recovery codes" do
      user = user()
      session = Users.generate_user_session_token(user)
      refute TwoFactor.enabled?(user)

      {{:ok, passkey, codes}, _authenticator} = register(user)
      assert passkey.name == "Laptop"
      assert length(codes) == 10
      assert TwoFactor.enabled?(user)
      refute TwoFactor.totp_enabled?(user)
      # As turning on the app does, the first second factor ends other sessions
      refute Users.get_user_by_session_token(session)

      {{:ok, _second, nil}, _} = register(user, "Phone")
      assert length(Passkeys.list(user)) == 2

      email = user.email
      assert_received {:email, %{to: [{"", ^email}], subject: "A passkey was added"}}

      assert [:passkey_added, :passkey_added] =
               Repo.all(from e in SecurityEvent, where: e.user_id == ^user.id, select: e.action, order_by: e.id)
    end

    test "a passkey belongs to one account" do
      authenticator = SoftAuthenticator.new()
      {{:ok, _, _}, _} = register(user(), "Mine", authenticator)
      assert {{:error, :already_registered}, _} = register(user(), "Theirs", authenticator)
    end

    test "refuses an answer to another challenge, or from another origin" do
      user = user()
      {:ok, challenge, options} = Passkeys.start_registration(user, "admin")
      {:ok, other, _options} = Passkeys.start_registration(user, "admin")
      authenticator = SoftAuthenticator.new()

      assert {:error, :invalid} =
               Passkeys.register(user, "x", SoftAuthenticator.register(authenticator, options, origin()), other)

      assert {:error, :invalid} =
               Passkeys.register(
                 user,
                 "x",
                 SoftAuthenticator.register(authenticator, options, "https://evil.test"),
                 challenge
               )

      assert Passkeys.list(user) == []
    end

    test "registration options exclude the user's passkeys, and hide who they are" do
      user = user()
      {{:ok, passkey, _}, _} = register(user)
      {:ok, _challenge, options} = Passkeys.start_registration(user, "admin")

      assert [%{id: id}] = options.excludeCredentials
      assert id == Base.url_encode64(passkey.credential_id, padding: false)
      # An HMAC of the id, not the id: a 32-byte handle that doesn't decode to it
      handle = Base.url_decode64!(options.user.id, padding: false)
      assert byte_size(handle) == 32
      refute handle == to_string(user.id)
      assert options.authenticatorSelection.residentKey == "preferred"
    end
  end

  describe "authenticating" do
    test "accepts the user's passkey, and notes its use" do
      user = user()
      {{:ok, passkey, _}, authenticator} = register(user)

      assert {:ok, user_id, used} = assert_with(user, authenticator, sign_count: 1)
      assert user_id == user.id
      assert used.sign_count == 1
      assert Repo.get!(Passkey, passkey.id).last_used_at
    end

    test "logs in with a passkey alone, which must verify the user" do
      user = user()
      {{:ok, _, _}, authenticator} = register(user)

      assert {:ok, user_id, _} = assert_with(:any, authenticator)
      assert user_id == user.id
      assert {:error, :invalid} = assert_with(:any, authenticator, user_verified: false)
    end

    test "refuses another user's passkey, a forged signature, and an unknown one" do
      user = user()
      other = user()
      {{:ok, _, _}, authenticator} = register(user)
      {{:ok, _, _}, _} = register(other)

      assert {:error, :unknown_passkey} = assert_with(other, authenticator)
      assert {:error, :unknown_passkey} = assert_with(user, SoftAuthenticator.new())

      {challenge, options} = Passkeys.authentication_challenge(user)
      forged = %{authenticator | private_key: SoftAuthenticator.new().private_key}
      result = SoftAuthenticator.assert(forged, options, origin: origin())
      assert {:error, :invalid} = Passkeys.authenticate(user, result, challenge)
    end

    test "an answer works for its own challenge only" do
      user = user()
      {{:ok, _, _}, authenticator} = register(user)
      {challenge, options} = Passkeys.authentication_challenge(user)
      {_other, other_options} = Passkeys.authentication_challenge(user)

      result = SoftAuthenticator.assert(authenticator, options, origin: origin(), challenge: other_options.challenge)
      assert {:error, :invalid} = Passkeys.authenticate(user, result, challenge)
    end

    test "an expired challenge is refused" do
      user = user()
      {{:ok, _, _}, authenticator} = register(user)
      {challenge, options} = Passkeys.authentication_challenge(user)
      result = SoftAuthenticator.assert(authenticator, options, origin: origin())

      assert {:error, :invalid} = Passkeys.authenticate(user, result, %{challenge | issued_at: challenge.issued_at - 301})
    end

    test "a counter that goes backwards is refused" do
      user = user()
      {{:ok, _, _}, authenticator} = register(user)

      assert {:ok, _, _} = assert_with(user, authenticator, sign_count: 5)
      assert {:error, :counter} = assert_with(user, authenticator, sign_count: 5)
      assert {:error, :counter} = assert_with(user, authenticator, sign_count: 3)
      assert {:ok, _, _} = assert_with(user, authenticator, sign_count: 6)
    end

    test "a challenge kept in the session is rebuilt to the same one" do
      user = user()
      {{:ok, _, _}, authenticator} = register(user)
      {challenge, options} = Passkeys.authentication_challenge(user)
      restored = Passkeys.restore_authentication_challenge(user, challenge.bytes, challenge.issued_at)

      result = SoftAuthenticator.assert(authenticator, options, origin: origin())
      assert {:ok, _, _} = Passkeys.authenticate(user, result, restored)
    end
  end

  describe "with the sign-in policy" do
    setup do
      admin = user(role: :superuser)
      register(admin)
      {:ok, _} = SecurityPolicy.update(%{"two_factor" => "everyone"}, admin)
      :ok
    end

    test "a passkey satisfies it, and the last one cannot be removed" do
      user = user()
      assert TwoFactor.must_enroll?(user)
      without = SecurityPolicy.without_two_factor_count(SecurityPolicy.get())

      {{:ok, passkey, _}, _} = register(user)
      refute TwoFactor.must_enroll?(user)
      # The policy's count of users without it counts passkeys too
      assert SecurityPolicy.without_two_factor_count(SecurityPolicy.get()) == without - 1
      assert {:error, :required} = Passkeys.delete(user, passkey.id)

      {{:ok, _second, _}, _} = register(user, "Phone")
      assert :ok = Passkeys.delete(user, passkey.id)
    end

    test "the app can be turned off when a passkey remains" do
      user = user()
      secret = TwoFactor.new_secret()
      {:ok, _codes} = TwoFactor.enable(user, secret, TwoFactor.current_code(secret), proof: "admin")
      assert {:error, :required} = TwoFactor.disable(user, "admin")

      {{:ok, _, nil}, _} = register(user)
      assert :ok = TwoFactor.disable(user, "admin")
      assert TwoFactor.enabled?(user)
      # The recovery codes stay with the passkey
      assert TwoFactor.recovery_codes_left(user) == 10
    end
  end

  test "removing the last second factor removes the recovery codes" do
    user = user()
    {{:ok, passkey, _}, _} = register(user)
    assert TwoFactor.recovery_codes_left(user) == 10

    assert :ok = Passkeys.delete(user, passkey.id)
    refute TwoFactor.enabled?(user)
    assert TwoFactor.recovery_codes_left(user) == 0
    email = user.email
    assert_received {:email, %{to: [{"", ^email}], subject: "A passkey was removed"}}
    assert {:error, :not_found} = Passkeys.delete(user, passkey.id)
  end

  test "an administrator's reset removes the passkeys too" do
    admin = user(role: :superuser)
    user = user()
    {{:ok, _, _}, _} = register(user)

    assert {:ok, _} = TwoFactor.reset(user.id, admin)
    assert Passkeys.list(user) == []
    refute TwoFactor.enabled?(user)
  end
end

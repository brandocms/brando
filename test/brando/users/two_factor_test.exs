defmodule Brando.Users.TwoFactorTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Users
  alias Brando.Users.RecoveryCode
  alias Brando.Users.Security
  alias Brando.Users.SecurityEvent
  alias Brando.Users.SecurityPolicy
  alias Brando.Users.TwoFactor
  alias Brando.Users.UserConfig

  defp user(attrs \\ []), do: Factory.insert(:random_user, Keyword.merge([config: %UserConfig{}], attrs))

  defp code_at(secret, step_offset),
    do: NimbleTOTP.verification_code(secret, time: System.os_time(:second) + step_offset * 30)

  defp enable(user) do
    secret = TwoFactor.new_secret()
    {:ok, codes} = TwoFactor.enable(user, secret, TwoFactor.current_code(secret))
    # The code that turned it on is used up; let the tests use the current
    # step again.
    Repo.update_all(from(s in Security, where: s.user_id == ^user.id), set: [totp_last_step: nil])
    {secret, codes}
  end

  defp actions(user) do
    Repo.all(from e in SecurityEvent, where: e.user_id == ^user.id, order_by: [asc: e.id], select: e.action)
  end

  describe "turning it on" do
    test "needs a code the app shows for the new secret" do
      user = user()
      secret = TwoFactor.new_secret()

      assert {:error, :invalid_code} = TwoFactor.enable(user, secret, "000000")
      refute TwoFactor.enabled?(user)

      assert {:ok, codes} = TwoFactor.enable(user, secret, TwoFactor.current_code(secret))
      assert TwoFactor.enabled?(user)
      assert length(codes) == 10
      assert Enum.all?(codes, &(&1 =~ ~r/^[a-z2-9]{5}-[a-z2-9]{5}$/))
      assert TwoFactor.recovery_codes_left(user) == 10
      assert :two_factor_enabled in actions(user)
    end

    test "logs out the other sessions, keeping the current one" do
      user = user()
      current = Users.generate_user_session_token(user)
      other = Users.generate_user_session_token(user)
      secret = TwoFactor.new_secret()

      {:ok, _codes} = TwoFactor.enable(user, secret, TwoFactor.current_code(secret), keep_token: current)

      assert Users.get_user_by_session_token(current)
      refute Users.get_user_by_session_token(other)
    end

    test "the QR code and key carry the secret" do
      user = user()
      secret = TwoFactor.new_secret()
      uri = TwoFactor.otpauth_uri(user, secret)

      assert uri =~ "otpauth://totp/"
      assert uri =~ "secret=" <> Base.encode32(secret, padding: false)
      assert TwoFactor.qr_code_svg(uri) =~ ~r/\A<svg /
      assert String.replace(TwoFactor.display_secret(secret), " ", "") == Base.encode32(secret, padding: false)
    end
  end

  describe "encryption at rest" do
    test "the stored secret is encrypted for the user, and only decrypts for them" do
      user = user()
      {secret, _codes} = enable(user)

      %{rows: [[stored]]} = Repo.query!("SELECT totp_secret FROM users_security WHERE user_id = $1", [user.id])

      refute stored =~ Base.encode32(secret, padding: false)
      refute String.contains?(stored, secret)
      assert {:ok, ^secret} = Brando.Crypto.decrypt(stored, "users.totp_secret:#{user.id}")
      assert :error = Brando.Crypto.decrypt(stored, "users.totp_secret:#{user.id + 1}")
    end

    test "recovery codes are stored as keyed hashes" do
      user = user()
      {_secret, [code | _]} = enable(user)

      hashes = Repo.all(from c in RecoveryCode, where: c.user_id == ^user.id, select: c.hashed_code)
      refute Enum.any?(hashes, &String.contains?(&1, String.replace(code, "-", "")))
      refute :crypto.hash(:sha256, String.replace(code, "-", "")) in hashes
    end
  end

  describe "codes" do
    test "accepts the app's code, and one step either side" do
      user = user()
      {secret, _codes} = enable(user)

      assert {:ok, :totp} = TwoFactor.verify(user, code_at(secret, -1))
      assert {:ok, :totp} = TwoFactor.verify(user, code_at(secret, 0))
      assert {:ok, :totp} = TwoFactor.verify(user, code_at(secret, 1))
      refute TwoFactor.valid_totp?(user, code_at(secret, 3))
    end

    test "a code works once, and an older one never after it" do
      user = user()
      {secret, _codes} = enable(user)
      code = code_at(secret, 0)

      assert {:ok, :totp} = TwoFactor.verify(user, code)
      assert {:error, :invalid} = TwoFactor.verify(user, code)
      assert {:error, :invalid} = TwoFactor.verify(user, code_at(secret, -1))
      assert {:ok, :totp} = TwoFactor.verify(user, code_at(secret, 1))
    end

    test "rejects anything else" do
      user = user()
      enable(user)

      assert {:error, :invalid} = TwoFactor.verify(user, "")
      assert {:error, :invalid} = TwoFactor.verify(user, nil)
      assert {:error, :invalid} = TwoFactor.verify(user, "12345")
      assert {:error, :invalid} = TwoFactor.verify(user, "abcde-fghij")
    end

    test "a user without two-factor authentication has no valid codes" do
      user = user()
      refute TwoFactor.valid_totp?(user, "123456")
    end
  end

  describe "recovery codes" do
    test "each works once, written any way" do
      user = user()
      {_secret, [first, second | _]} = enable(user)

      assert {:ok, :recovery_code} = TwoFactor.verify(user, first)
      assert {:error, :invalid} = TwoFactor.verify(user, first)
      assert {:ok, :recovery_code} = TwoFactor.verify(user, " " <> String.upcase(String.replace(second, "-", "")))
      assert TwoFactor.recovery_codes_left(user) == 8
    end

    test "one user's code does not work for another" do
      user = user()
      other = user()
      {_secret, [code | _]} = enable(user)
      enable(other)

      assert {:error, :invalid} = TwoFactor.verify(other, code)
    end

    test "making new ones asks for the password or a code, and replaces the old" do
      user = user()
      {secret, [old | _]} = enable(user)

      assert {:error, :invalid_proof} = TwoFactor.regenerate_recovery_codes(user, "wrong")
      assert {:ok, new_codes} = TwoFactor.regenerate_recovery_codes(user, "admin")
      assert {:error, :invalid} = TwoFactor.verify(user, old)
      assert {:ok, :recovery_code} = TwoFactor.verify(user, hd(new_codes))

      assert {:ok, _codes} = TwoFactor.regenerate_recovery_codes(user, TwoFactor.current_code(secret))
      assert :recovery_codes_created in actions(user)
    end
  end

  describe "turning it off" do
    test "asks for the password or a current code" do
      user = user()
      {secret, _codes} = enable(user)

      assert {:error, :invalid_proof} = TwoFactor.disable(user, "wrong password")
      assert TwoFactor.enabled?(user)

      assert :ok = TwoFactor.disable(user, TwoFactor.current_code(secret))
      refute TwoFactor.enabled?(user)
      assert TwoFactor.recovery_codes_left(user) == 0
      assert :two_factor_disabled in actions(user)
    end

    test "a recovery code is not enough" do
      user = user()
      {_secret, [code | _]} = enable(user)
      assert {:error, :invalid_proof} = TwoFactor.disable(user, code)
    end

    test "not while the sign-in policy requires it" do
      admin = user(role: :superuser)
      user = user(role: :editor)
      enable(admin)
      enable(user)
      {:ok, _policy} = SecurityPolicy.update(%{"two_factor" => "everyone"}, admin)

      assert {:error, :required} = TwoFactor.disable(user, "admin")
    end
  end

  describe "an administrator's reset" do
    test "turns it off, ends the lockout and the sessions, and is logged" do
      admin = user(role: :superuser)
      user = user(role: :editor)
      enable(user)
      session = Users.generate_user_session_token(user)
      Repo.insert!(%Security{user_id: user.id, failed_attempts: 0}, on_conflict: :nothing, conflict_target: :user_id)

      Repo.update_all(from(s in Security, where: s.user_id == ^user.id),
        set: [locked_until: DateTime.add(DateTime.utc_now(:second), 600)]
      )

      assert {:ok, _user} = TwoFactor.reset(user.id, admin)
      refute TwoFactor.enabled?(user)
      refute Brando.Users.Throttle.locked_until(user)
      refute Users.get_user_by_session_token(session)

      assert [%{actor_id: actor_id}] =
               Repo.all(from e in SecurityEvent, where: e.user_id == ^user.id and e.action == :two_factor_reset)

      assert actor_id == admin.id
    end

    test "is for superusers, and not for your own account" do
      admin = user(role: :superuser)
      editor = user(role: :editor)
      user = user(role: :editor)
      enable(user)
      enable(admin)

      assert {:error, :forbidden} = TwoFactor.reset(user.id, editor)
      assert {:error, :forbidden} = TwoFactor.reset(admin.id, admin)
      assert TwoFactor.enabled?(user)
    end
  end

  describe "the sign-in policy" do
    test "requires it of everyone, or of the roles it names" do
      admin = user(role: :superuser)
      editor = user(role: :editor)
      enable(admin)

      refute TwoFactor.required?(editor)

      {:ok, _} = SecurityPolicy.update(%{"two_factor" => "selected", "two_factor_roles" => ["admin"]}, admin)
      refute TwoFactor.required?(editor)

      {:ok, _} = SecurityPolicy.update(%{"two_factor" => "selected", "two_factor_roles" => ["editor"]}, admin)
      assert TwoFactor.required?(editor)
      assert TwoFactor.must_enroll?(editor)
      assert SecurityPolicy.without_two_factor_count(SecurityPolicy.get()) >= 1

      {:ok, _} = SecurityPolicy.update(%{"two_factor" => "everyone"}, admin)
      assert TwoFactor.required?(admin)
      refute TwoFactor.must_enroll?(admin)
    end

    test "only a superuser saves it, and only once they use two-factor authentication if it applies to them" do
      admin = user(role: :superuser)
      editor = user(role: :editor)

      assert {:error, :forbidden} = SecurityPolicy.update(%{"two_factor" => "everyone"}, editor)
      assert {:error, :enroll_first} = SecurityPolicy.update(%{"two_factor" => "everyone"}, admin)

      assert {:ok, _} =
               SecurityPolicy.update(%{"two_factor" => "selected", "two_factor_roles" => ["editor"]}, admin)

      assert [:policy_changed] = actions(admin)
    end

    test "ends the session of a user who must now set it up" do
      admin = user(role: :superuser)
      editor = user(role: :editor)
      enable(admin)
      session = Users.generate_user_session_token(editor)
      assert Users.get_user_by_session_token(session)

      {:ok, _} = SecurityPolicy.update(%{"two_factor" => "everyone"}, admin)

      refute Users.get_user_by_session_token(session)
      refute Repo.get_by(Brando.Users.UserToken, token: session)
    end
  end

  test "content transfer leaves sign-in security out" do
    user = user()
    other = user()
    enable(user)

    tables = user.id |> Users.get_user_content_summary() |> Enum.map(& &1.table)
    refute Enum.any?(tables, &String.starts_with?(&1, "users_"))

    assert {:ok, _} = Users.transfer_user_content(user.id, other.id)
    refute TwoFactor.enabled?(other)
    assert Repo.all(from e in SecurityEvent, where: e.user_id == ^other.id) == []
  end
end

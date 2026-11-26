defmodule Brando.Doctor.EncryptionSecretTest do
  use ExUnit.Case, async: true

  alias Brando.Doctor.Checks.EncryptionSecret
  alias Brando.Doctor.Result

  @secret_key_base String.duplicate("signs-sessions-", 5)
  @own String.duplicate("encrypts-values-", 3)

  test "a secret of its own is fine" do
    assert %Result{status: :ok} = EncryptionSecret.evaluate(@own, @secret_key_base)
  end

  test "without one, Brando uses the endpoint's secret_key_base: a warning with the fix" do
    assert %Result{status: :warning, summary: summary, fix: fix} = EncryptionSecret.evaluate(nil, @secret_key_base)
    assert summary =~ "secret_key_base"
    assert fix =~ "BRANDO_ENCRYPTION_SECRET"
    assert fix =~ "config/dev.secret.exs"
  end

  test "a secret two-factor sign-in cannot use is an error" do
    for secret <- ["", "too short", 42, ~c"a charlist of more than thirty-two characters"] do
      assert %Result{status: :error, fix: fix} = EncryptionSecret.evaluate(secret, @secret_key_base), inspect(secret)
      assert fix =~ "Brando.Crypto"
    end

    # Neither a secret nor a usable secret_key_base
    assert %Result{status: :error} = EncryptionSecret.evaluate(nil, nil)
  end

  test "the installer's placeholder, never filled in, is an error naming the files" do
    assert %Result{status: :error, fix: fix} =
             EncryptionSecret.evaluate("__BRANDO_ENCRYPTION_SECRET__", @secret_key_base)

    for file <- ~w(.envrc.prod .envrc.staging config/dev.secret.exs), do: assert(fix =~ file)
  end

  test "the same value as the endpoint's secret_key_base warns until it is replaced" do
    assert %Result{status: :warning, fix: fix} = EncryptionSecret.evaluate(@secret_key_base, @secret_key_base)
    assert fix =~ "SECRET_KEY_BASE"
  end

  test "runs against the application's configuration, and is one of Brando's checks" do
    # config/test.exs gives the test application a secret of its own
    assert %Result{status: :ok} = EncryptionSecret.run(Brando.Doctor.Context.new([]))
    assert EncryptionSecret in Brando.Doctor.default_checks()
  end
end

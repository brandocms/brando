defmodule Brando.CryptoTest do
  use ExUnit.Case, async: false

  import Brando.Test.Support, only: [put_test_env: 2]

  alias Brando.Crypto

  test "encrypts with the configured secret, not the endpoint's secret_key_base" do
    ciphertext = Crypto.encrypt("a value", "context")
    assert {:ok, "a value"} = Crypto.decrypt(ciphertext, "context")

    put_test_env(Brando.Crypto, secret: String.duplicate("another-site's-", 3))
    assert :error = Crypto.decrypt(ciphertext, "context")
  end

  test "the installer's placeholder, never filled in, raises naming the files to fill" do
    put_test_env(Brando.Crypto, secret: "__BRANDO_ENCRYPTION_SECRET__")

    error = assert_raise ArgumentError, fn -> Crypto.encrypt("a value", "context") end
    assert error.message =~ "mix brando.install"
    assert error.message =~ "config/dev.secret.exs"
  end
end

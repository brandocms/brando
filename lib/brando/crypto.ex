defmodule Brando.Crypto do
  @moduledoc """
  Encryption and keyed hashing for secrets Brando keeps in the database, such
  as a user's two-factor secret and recovery codes.

  Keys are derived from one secret with `Plug.Crypto.KeyGenerator`, a
  separate key for each purpose. The secret is the endpoint's
  `secret_key_base`, unless the application sets its own:

      config :brando, Brando.Crypto, secret: System.fetch_env!("BRANDO_ENCRYPTION_SECRET")

  Either way, it must stay the same: with a new secret, encrypted values can
  no longer be read and hashed codes no longer match. Users would have to set
  up two-factor authentication again. Set a dedicated secret if
  `secret_key_base` may be rotated.

  Encryption is `Plug.Crypto.MessageEncryptor` (XChaCha20-Poly1305). The
  `context` given to `encrypt/2` is bound to the ciphertext as additional
  authenticated data, so a value copied to another place does not decrypt.
  """

  alias Plug.Crypto.KeyGenerator
  alias Plug.Crypto.MessageEncryptor

  @doc "Encrypts `plaintext` for `context`, such as `\"users.totp_secret:12\"`."
  @spec encrypt(binary(), String.t()) :: String.t()
  def encrypt(plaintext, context) when is_binary(plaintext) and is_binary(context) do
    MessageEncryptor.encrypt(plaintext, context, key("brando encrypted value"), "")
  end

  @doc "Decrypts what `encrypt/2` returned for the same `context`."
  @spec decrypt(String.t() | nil, String.t()) :: {:ok, binary()} | :error
  def decrypt(ciphertext, context) when is_binary(ciphertext) and is_binary(context) do
    MessageEncryptor.decrypt(ciphertext, context, key("brando encrypted value"), "")
  end

  def decrypt(_ciphertext, _context), do: :error

  @doc """
  A keyed SHA-256 hash of `data` for `purpose`. Someone with a copy of the
  database but not the secret cannot test guesses against it.
  """
  @spec hmac(binary(), String.t()) :: binary()
  def hmac(data, purpose) when is_binary(data) and is_binary(purpose) do
    :crypto.mac(:hmac, :sha256, key("brando hmac " <> purpose), data)
  end

  defp key(salt), do: KeyGenerator.generate(secret(), salt, length: 32, cache: Plug.Crypto.Keys)

  defp secret do
    case Brando.config(__MODULE__)[:secret] || Brando.endpoint().config(:secret_key_base) do
      secret when is_binary(secret) and byte_size(secret) >= 32 ->
        secret

      _ ->
        raise ArgumentError,
              "Brando.Crypto needs a secret of at least 32 bytes: set the endpoint's :secret_key_base, " <>
                "or config :brando, Brando.Crypto, secret: ..."
    end
  end
end

defmodule Brando.Test.SoftAuthenticator do
  @moduledoc """
  A software WebAuthn authenticator for tests: an ES256 key pair, "none"
  attestation, and the browser's side of `navigator.credentials` — it answers
  the options `Brando.Users.Passkeys` makes with what the `Brando.Passkey`
  hook would post back, Base64url-encoded.
  """

  defstruct [:credential_id, :private_key, :public_key, sign_count: 0]

  @flag_user_present 0x01
  @flag_user_verified 0x04
  @flag_attested_credential_data 0x40

  def new do
    {public_key, private_key} = :crypto.generate_key(:ecdh, :secp256r1)
    %__MODULE__{credential_id: :crypto.strong_rand_bytes(32), private_key: private_key, public_key: public_key}
  end

  @doc "The browser's answer to registration `options` (the `publicKey` map)."
  def register(%__MODULE__{} = authenticator, options, origin) do
    client_data =
      Jason.encode!(%{type: "webauthn.create", challenge: options.challenge, origin: origin, crossOrigin: false})

    <<4, x::binary-size(32), y::binary-size(32)>> = authenticator.public_key
    cose_key = %{1 => 2, 3 => -7, -1 => 1, -2 => bytes(x), -3 => bytes(y)}
    id = authenticator.credential_id

    auth_data =
      :crypto.hash(:sha256, options.rp.id) <>
        <<@flag_user_present + @flag_user_verified + @flag_attested_credential_data, authenticator.sign_count::32>> <>
        <<0::128, byte_size(id)::16>> <> id <> CBOR.encode(cose_key)

    attestation_object = CBOR.encode(%{"fmt" => "none", "attStmt" => %{}, "authData" => bytes(auth_data)})

    %{
      "id" => encode(id),
      "attestation_object" => encode(attestation_object),
      "client_data_json" => encode(client_data)
    }
  end

  @doc """
  The browser's answer to request `options`. `opts`: `:origin` (required),
  `:sign_count`, `:user_verified` (default true), `:challenge` to answer
  another challenge than the options'.
  """
  def assert(%__MODULE__{} = authenticator, options, opts) do
    challenge = Keyword.get(opts, :challenge, options.challenge)
    client_data = Jason.encode!(%{type: "webauthn.get", challenge: challenge, origin: Keyword.fetch!(opts, :origin)})
    flags = @flag_user_present + if(Keyword.get(opts, :user_verified, true), do: @flag_user_verified, else: 0)

    auth_data =
      :crypto.hash(:sha256, options.rpId) <> <<flags, Keyword.get(opts, :sign_count, authenticator.sign_count)::32>>

    signature =
      :crypto.sign(:ecdsa, :sha256, auth_data <> :crypto.hash(:sha256, client_data), [
        authenticator.private_key,
        :secp256r1
      ])

    %{
      "id" => encode(authenticator.credential_id),
      "authenticator_data" => encode(auth_data),
      "signature" => encode(signature),
      "client_data_json" => encode(client_data),
      "user_handle" => ""
    }
  end

  defp bytes(binary), do: %CBOR.Tag{tag: :bytes, value: binary}
  defp encode(binary), do: Base.url_encode64(binary, padding: false)
end

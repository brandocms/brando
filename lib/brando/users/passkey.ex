defmodule Brando.Users.Passkey do
  @moduledoc """
  A passkey: a WebAuthn credential on one of a user's devices. `name` is what
  the user called the device; `credential_id` and `cose_key` are the
  credential and its public key; `sign_count` is the authenticator's
  signature counter. See `Brando.Users.Passkeys`.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @schema_prefix "public"

  schema "users_passkeys" do
    belongs_to :user, Brando.Users.User
    field :name, :string
    field :credential_id, :binary
    field :cose_key, :binary, redact: true
    field :sign_count, :integer, default: 0
    field :aaguid, :binary
    field :last_used_at, :utc_datetime
    timestamps()
  end
end

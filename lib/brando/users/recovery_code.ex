defmodule Brando.Users.RecoveryCode do
  @moduledoc """
  A one-time recovery code for two-factor authentication. Only its keyed hash
  is stored (`Brando.Crypto.hmac/2`); the code itself is shown once, when it
  is made. See `Brando.Users.TwoFactor`.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @schema_prefix "public"

  schema "users_recovery_codes" do
    belongs_to :user, Brando.Users.User
    field :hashed_code, :binary, redact: true
    field :used_at, :utc_datetime
    timestamps(updated_at: false)
  end
end

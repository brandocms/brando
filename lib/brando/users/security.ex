defmodule Brando.Users.Security do
  @moduledoc """
  A user's sign-in security: the encrypted TOTP secret, when two-factor
  authentication was turned on, the last time step a code was accepted for,
  and failed attempts and lockout. See `Brando.Users.TwoFactor` and
  `Brando.Users.Throttle`.

  Kept apart from `Brando.Users.User`, whose blueprint form casts every
  attribute: none of these may be set from a form.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  @schema_prefix "public"

  schema "users_security" do
    belongs_to :user, Brando.Users.User
    field :totp_secret, :string, redact: true
    field :totp_enabled_at, :utc_datetime
    field :totp_last_step, :integer
    field :failed_attempts, :integer, default: 0
    field :locked_until, :utc_datetime
    timestamps()
  end
end

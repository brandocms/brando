defmodule Brando.Users.SecurityEvent do
  @moduledoc """
  Something that happened to a user's sign-in security: a sign-in, a failed
  one, a lockout, or a change to their password or two-factor settings.
  `actor` is who did it when that was someone else, such as an administrator
  resetting two-factor authentication. See `Brando.Users.SecurityLog`.
  """
  use Ecto.Schema

  @actions [
    :login,
    :login_failed,
    :locked,
    :two_factor_enabled,
    :two_factor_disabled,
    :two_factor_reset,
    :recovery_codes_created,
    :password_changed,
    :policy_changed
  ]

  @type t :: %__MODULE__{}

  @schema_prefix "public"

  schema "users_security_events" do
    belongs_to :user, Brando.Users.User
    belongs_to :actor, Brando.Users.User
    field :action, Ecto.Enum, values: @actions
    field :ip, :string
    field :user_agent, :string
    field :details, :map, default: %{}
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc "The actions an event can record."
  def actions, do: @actions
end

defmodule Brando.Notifications.Delivery do
  @moduledoc """
  One notification sent on one route: to the route's Slack or Teams webhook,
  or, for an email route, to one of its recipients. `notification` holds
  what the message says (see `Brando.Notifications.Message`); the message is
  built from it when it is sent, in the recipient's language for email.

  States: `pending` (queued), `sending`, `retrying` (failed, will be tried
  again), `succeeded`, `failed` (gave up), `cancelled` (the route was paused,
  or the recipient may no longer have it) and `digest` (waiting for the
  recipient's next email, or their summary).

  Several Slack or Teams deliveries of the same event on a route, queued
  within `Brando.Notifications.Routing.burst_seconds/0` of each other, go
  out as one message: the others name it in `grouped_into_id` and take its
  state.
  """
  use Ecto.Schema

  @states ~w(pending sending retrying succeeded failed cancelled digest)

  @type t :: %__MODULE__{}

  schema "notification_deliveries" do
    belongs_to :route, Brando.Notifications.Route
    belongs_to :recipient, Brando.Users.User
    field :event, :string
    field :event_id, Ecto.UUID
    field :entry_schema, :string
    field :entry_type, :string
    field :entry_id, :integer
    field :notification, :map
    field :state, :string, default: "pending"
    field :attempts, :integer, default: 0
    field :response_status, :integer
    field :response_body, :string
    field :error, :string
    field :duration_ms, :integer
    field :test, :boolean, default: false
    field :grouped_into_id, :integer
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def states, do: @states
end

defmodule Brando.Webhooks.Delivery do
  @moduledoc """
  One event sent to one webhook: the payload, whether and when it arrived,
  the response code, how long it took, and the first 4 KB of the response
  body. A redelivery or a test event is a delivery of its own.

  States: `pending` (queued), `sending`, `retrying` (failed, will be tried
  again), `succeeded`, `failed` (gave up) and `cancelled` (the webhook was
  paused or deleted before it was sent).
  """
  use Ecto.Schema

  @states ~w(pending sending retrying succeeded failed cancelled)

  @type t :: %__MODULE__{}

  schema "webhook_deliveries" do
    belongs_to :webhook, Brando.Webhooks.Webhook
    field :delivery_id, Ecto.UUID
    field :event_id, Ecto.UUID
    field :event, :string
    field :entry_schema, :string
    field :entry_type, :string
    field :entry_id, :integer
    field :language, :string
    field :payload, :map
    field :state, :string, default: "pending"
    field :attempts, :integer, default: 0
    field :response_status, :integer
    field :response_body, :string
    field :error, :string
    field :duration_ms, :integer
    field :test, :boolean, default: false
    field :redelivery_of_id, :integer
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def states, do: @states
end

defmodule BrandoIntegration.Repo.Migrations.AddNotificationRoutes do
  use Ecto.Migration

  # Mirrors the brando_217 upgrade migration for the test schema.
  @moduledoc """
  Notifications to Slack, Teams and email (`Brando.Notifications`): the
  routes a site environment sends them on, and the log of what was sent.
  """

  def change do
    create table(:notification_routes) do
      add :name, :text, null: false
      add :kind, :string, null: false
      add :events, {:array, :string}, null: false, default: []
      add :entry_types, {:array, :string}, null: false, default: []
      add :recipient_ids, {:array, :integer}, null: false, default: []
      add :url_ciphertext, :text
      add :url_hint, :string
      add :active, :boolean, null: false, default: true
      add :paused_reason, :string
      add :paused_at, :utc_datetime_usec
      add :failing_since, :utc_datetime_usec
      add :last_delivery_at, :utc_datetime_usec
      add :last_delivery_state, :string
      add :creator_id, references(:users, prefix: "public", on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create table(:notification_deliveries) do
      add :route_id, references(:notification_routes, on_delete: :delete_all), null: false
      add :event, :string, null: false
      add :event_id, :uuid
      add :recipient_id, references(:users, prefix: "public", on_delete: :delete_all)
      add :entry_schema, :string
      add :entry_type, :string
      add :entry_id, :integer
      add :notification, :map, null: false
      add :state, :string, null: false, default: "pending"
      add :attempts, :integer, null: false, default: 0
      add :response_status, :integer
      add :response_body, :text
      add :error, :text
      add :duration_ms, :integer
      add :test, :boolean, null: false, default: false
      add :grouped_into_id, :bigint
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:notification_deliveries, [:route_id, :inserted_at])
    create index(:notification_deliveries, [:inserted_at])
    create index(:notification_deliveries, [:recipient_id, :state])

    create unique_index(:notification_deliveries, [:route_id, :event_id, "coalesce(recipient_id, 0)"],
             where: "event_id IS NOT NULL",
             name: :notification_deliveries_once_per_event_index
           )
  end
end

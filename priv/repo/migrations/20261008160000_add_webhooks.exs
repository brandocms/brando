defmodule BrandoIntegration.Repo.Migrations.AddWebhooks do
  use Ecto.Migration

  # Mirrors the brando_209 upgrade migration for the test schema.
  @moduledoc """
  Outbound webhooks (`Brando.Webhooks`): the endpoints a site environment
  calls when its content changes, and the log of what was sent to them.
  """

  def change do
    create table(:webhooks) do
      add :name, :text, null: false
      add :url, :text, null: false
      add :events, {:array, :string}, null: false, default: []
      add :entry_types, {:array, :string}, null: false, default: []
      add :languages, {:array, :string}, null: false, default: []
      add :active, :boolean, null: false, default: true
      add :paused_reason, :string
      add :paused_at, :utc_datetime_usec
      add :secret_ciphertext, :text, null: false
      add :secret_hint, :string
      add :secret_rotated_at, :utc_datetime_usec
      add :failing_since, :utc_datetime_usec
      add :last_delivery_at, :utc_datetime_usec
      add :last_delivery_state, :string
      add :creator_id, references(:users, prefix: "public", on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create table(:webhook_deliveries) do
      add :webhook_id, references(:webhooks, on_delete: :delete_all), null: false
      add :delivery_id, :uuid, null: false
      add :event_id, :uuid
      add :event, :string, null: false
      add :entry_schema, :string
      add :entry_type, :string
      add :entry_id, :integer
      add :language, :string
      add :payload, :map, null: false
      add :state, :string, null: false, default: "pending"
      add :attempts, :integer, null: false, default: 0
      add :response_status, :integer
      add :response_body, :text
      add :error, :text
      add :duration_ms, :integer
      add :test, :boolean, null: false, default: false
      add :redelivery_of_id, :bigint
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:webhook_deliveries, [:delivery_id])
    create index(:webhook_deliveries, [:webhook_id, :inserted_at])
    create index(:webhook_deliveries, [:inserted_at])

    create unique_index(:webhook_deliveries, [:webhook_id, :event_id],
             where: "event_id IS NOT NULL AND redelivery_of_id IS NULL",
             name: :webhook_deliveries_once_per_event_index
           )
  end
end

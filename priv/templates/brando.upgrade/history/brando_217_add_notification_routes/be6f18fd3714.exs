defmodule Brando.Repo.Migrations.Brando217AddNotificationRoutes do
  use Ecto.Migration

  @moduledoc """
  In every site environment, the tables for notifications to Slack, Microsoft
  Teams and email (`Brando.Notifications`):

    * `notification_routes` holds where notifications go: a Slack or Teams
      incoming webhook, whose URL is stored encrypted with `Brando.Crypto`,
      or email to chosen users. Each route names the events it sends and,
      optionally, the content types.
    * `notification_deliveries` is the delivery log: what was sent where,
      the response code or error, and how long it took. An email waiting
      for a user's digest is a delivery too. Rows past
      `Brando.Webhooks.retention_days/0` are removed nightly.

  Users live in `public`, so their foreign keys name that schema.
  """

  def up do
    for prefix <- prefixes() do
      create table(:notification_routes, prefix: prefix) do
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

      create table(:notification_deliveries, prefix: prefix) do
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
        add :started_at, :utc_datetime_usec
        add :completed_at, :utc_datetime_usec

        timestamps(type: :utc_datetime_usec)
      end

      create index(:notification_deliveries, [:route_id, :inserted_at], prefix: prefix)
      create index(:notification_deliveries, [:inserted_at], prefix: prefix)
      create index(:notification_deliveries, [:recipient_id, :state], prefix: prefix)

      create unique_index(:notification_deliveries, [:route_id, :event_id, "coalesce(recipient_id, 0)"],
               prefix: prefix,
               where: "event_id IS NOT NULL",
               name: :notification_deliveries_once_per_event_index
             )
    end
  end

  def down do
    for prefix <- prefixes() do
      drop table(:notification_deliveries, prefix: prefix)
      drop table(:notification_routes, prefix: prefix)
    end
  end

  # Every site environment, or only the one named by the migrator's prefix:
  # `Brando.Environments.ArchiveUpgrade` runs this again in an archive
  # restored from before it ran.
  defp prefixes do
    case prefix() do
      "tenant_" <> _ = environment ->
        [environment]

      _ ->
        %{rows: rows} =
          repo().query!(
            "SELECT nspname FROM pg_namespace WHERE nspname = 'public' OR nspname ~ '^tenant_[a-z0-9-]+_[a-z0-9-]+$'"
          )

        Enum.map(rows, &hd/1)
    end
  end
end

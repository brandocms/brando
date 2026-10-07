defmodule Brando.Repo.Migrations.Brando209AddWebhooks do
  use Ecto.Migration

  @moduledoc """
  In every site environment, the tables for outbound webhooks
  (`Brando.Webhooks`):

    * `webhooks` holds the endpoints the environment calls when its content
      changes: the URL, the events and filters, whether it is active, and its
      signing secret, encrypted with `Brando.Crypto`.
    * `webhook_deliveries` is the delivery log: what was sent where, the
      response code, how long it took, and the first 4 KB of the response.
      Rows past `Brando.Webhooks.retention_days/0` are removed nightly.

  Users live in `public`, so their foreign keys name that schema.
  """

  def up do
    for prefix <- prefixes() do
      create table(:webhooks, prefix: prefix) do
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

      create table(:webhook_deliveries, prefix: prefix) do
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

      create unique_index(:webhook_deliveries, [:delivery_id], prefix: prefix)
      create index(:webhook_deliveries, [:webhook_id, :inserted_at], prefix: prefix)
      create index(:webhook_deliveries, [:inserted_at], prefix: prefix)

      create unique_index(:webhook_deliveries, [:webhook_id, :event_id],
               prefix: prefix,
               where: "event_id IS NOT NULL AND redelivery_of_id IS NULL",
               name: :webhook_deliveries_once_per_event_index
             )
    end
  end

  def down do
    for prefix <- prefixes() do
      drop table(:webhook_deliveries, prefix: prefix)
      drop table(:webhooks, prefix: prefix)
    end
  end

  defp prefixes do
    %{rows: rows} =
      repo().query!(
        "SELECT nspname FROM pg_namespace WHERE nspname = 'public' OR nspname ~ '^tenant_[a-z0-9-]+_[a-z0-9-]+$'"
      )

    Enum.map(rows, &hd/1)
  end
end

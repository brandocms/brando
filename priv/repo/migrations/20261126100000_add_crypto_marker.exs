defmodule BrandoIntegration.Repo.Migrations.AddCryptoMarker do
  use Ecto.Migration

  # Mirrors the brando_252 upgrade migration for the test schema.
  @moduledoc "The installation's encryption marker (`Brando.Crypto.Marker`)."

  def change do
    create table(:crypto_marker, primary_key: false, prefix: "public") do
      add :id, :smallint, primary_key: true, default: 1
      add :value, :text, null: false
      add :host, :text, null: false
      add :moved_from, :text
      add :moved_at, :utc_datetime_usec
      add :moved_key, :text
      add :paused, {:array, :map}, null: false, default: []
      add :paused_dismissed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:crypto_marker, :crypto_marker_one_row, check: "id = 1", prefix: "public")
  end
end

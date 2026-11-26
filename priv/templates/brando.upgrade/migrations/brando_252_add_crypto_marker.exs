defmodule Brando.Repo.Migrations.Brando252AddCryptoMarker do
  use Ecto.Migration

  @moduledoc """
  The installation's encryption marker (`crypto_marker`, one row, in
  `public`, `Brando.Crypto.Marker`): a value encrypted with the
  installation's secret and the host that wrote it, so a database written
  elsewhere is noticed at start.

  The table starts empty: the marker is written by the running application,
  with its own secret and host, at its first start after this migration.
  """

  def up do
    create_if_not_exists table(:crypto_marker, primary_key: false, prefix: "public") do
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

    execute("""
    DO $$ BEGIN
      ALTER TABLE public.crypto_marker ADD CONSTRAINT crypto_marker_one_row CHECK (id = 1);
    EXCEPTION WHEN duplicate_object THEN NULL;
    END $$
    """)
  end

  def down do
    drop_if_exists table(:crypto_marker, prefix: "public")
  end
end

defmodule Brando.Repo.Migrations.Brando189AddContentHashToImages do
  use Ecto.Migration

  @moduledoc """
  A fingerprint of each uploaded original (SHA-256), so an upload of a file
  the library already has can offer the existing image instead. Images from
  before this have none and are never matched.
  """

  def up do
    alter table(:images) do
      add :content_hash, :text
    end

    create index(:images, [:content_hash])
  end

  def down do
    drop index(:images, [:content_hash])

    alter table(:images) do
      remove :content_hash
    end
  end
end

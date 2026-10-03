defmodule Brando.Repo.Migrations.Brando196AddConfigFingerprintToImages do
  use Ecto.Migration

  @moduledoc """
  A fingerprint of the sizes and formats each image was processed with, so
  Utilities can recreate only the images whose config has changed. Images
  processed before this have none and count as changed.
  """

  def up do
    alter table(:images) do
      add :config_fingerprint, :text
    end
  end

  def down do
    alter table(:images) do
      remove :config_fingerprint
    end
  end
end

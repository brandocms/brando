defmodule Brando.Repo.Migrations.Brando197AddConfigFingerprintToImages do
  use Ecto.Migration

  @moduledoc """
  A fingerprint of the sizes and formats each image was processed with, so
  Utilities can recreate only the images whose config has changed. Images
  processed before this have none and count as changed.

  This shipped first as `brando_196`, sharing the number with
  `brando_196_add_form_notifications`, so a fresh install could not order the
  two. An application that copied it under the old name gets it again under
  this one; `add_if_not_exists` makes the second run a no-op.
  """

  def up do
    alter table(:images) do
      add_if_not_exists :config_fingerprint, :text
    end
  end

  def down do
    alter table(:images) do
      remove_if_exists :config_fingerprint, :text
    end
  end
end

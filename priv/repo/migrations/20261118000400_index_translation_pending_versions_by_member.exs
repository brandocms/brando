defmodule BrandoIntegration.Repo.Migrations.IndexTranslationPendingVersionsByMember do
  use Ecto.Migration

  # Mirrors the brando_235 upgrade migration for the test schema.
  @moduledoc """
  An index on `translation_pending_versions.member_id`, for reading a
  translation's work items across its whole history.
  """

  def change do
    create index(:translation_pending_versions, [:member_id])
  end
end

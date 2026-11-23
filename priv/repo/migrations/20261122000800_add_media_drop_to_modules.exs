defmodule BrandoIntegration.Repo.Migrations.AddMediaDropToModules do
  use Ecto.Migration

  # Mirrors the brando_246 upgrade migration for the test schema.
  @moduledoc """
  `content_modules.media_drop_child` and `media_drop_ref`: the child module a
  multi module creates for each file dropped on its blocks, and the ref of
  that child the file goes in.
  """

  def change do
    alter table(:content_modules) do
      add :media_drop_child, :text
      add :media_drop_ref, :text
    end
  end
end

defmodule BrandoIntegration.Repo.Migrations.AddWriteWithAIToModules do
  use Ecto.Migration

  # Mirrors the brando_218 upgrade migration for the test schema.
  @moduledoc """
  `content_modules.write_with_ai`: Write with AI in a module's text blocks,
  off until turned on in the module editor.
  """

  def change do
    alter table(:content_modules) do
      add :write_with_ai, :boolean, default: false
    end
  end
end

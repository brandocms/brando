defmodule BrandoIntegration.Repo.Migrations.AddKindToAiGuidanceVersions do
  use Ecto.Migration

  # Mirrors the brando_236 upgrade migration for the test schema.
  @moduledoc """
  `ai_guidance_versions.kind`: the content assistant's guidance
  (`assistant`) or the guidance for building from Figma (`figma`).
  """

  def change do
    alter table(:ai_guidance_versions, prefix: "public") do
      add :kind, :text, null: false, default: "assistant"
    end

    drop index(:ai_guidance_versions, [:scope, :inserted_at], prefix: "public")
    create index(:ai_guidance_versions, [:scope, :kind, :inserted_at], prefix: "public")
  end
end

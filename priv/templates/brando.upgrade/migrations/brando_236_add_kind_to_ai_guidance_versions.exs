defmodule Brando.Repo.Migrations.Brando236AddKindToAiGuidanceVersions do
  use Ecto.Migration

  @moduledoc """
  `ai_guidance_versions.kind`: which guidance a version belongs to. Existing
  versions are the content assistant's (`assistant`); the guidance connected
  AI tools get for building from Figma is `figma`. The index the latest
  version is looked up by takes the kind.
  """

  def up do
    alter table(:ai_guidance_versions, prefix: "public") do
      add_if_not_exists :kind, :text, null: false, default: "assistant"
    end

    drop_if_exists index(:ai_guidance_versions, [:scope, :inserted_at], prefix: "public")
    create_if_not_exists index(:ai_guidance_versions, [:scope, :kind, :inserted_at], prefix: "public")
  end

  def down do
    drop_if_exists index(:ai_guidance_versions, [:scope, :kind, :inserted_at], prefix: "public")
    execute "DELETE FROM public.ai_guidance_versions WHERE kind <> 'assistant'"

    alter table(:ai_guidance_versions, prefix: "public") do
      remove_if_exists :kind, :text
    end

    create_if_not_exists index(:ai_guidance_versions, [:scope, :inserted_at], prefix: "public")
  end
end

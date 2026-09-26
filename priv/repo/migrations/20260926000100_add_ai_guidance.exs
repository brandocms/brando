defmodule Brando.Repo.Migrations.Brando187AddAiGuidance do
  use Ecto.Migration

  @moduledoc """
  Site guidance for the content assistant, written in the admin. Every save
  adds a version; the latest version of a site/environment is the one in use.
  Like conversations it lives in `public`, so one site/environment can reuse
  another's guidance.
  """

  def change do
    create table(:ai_guidance_versions, primary_key: false, prefix: "public") do
      add :id, :uuid, primary_key: true
      add :scope, :text, null: false
      add :prefix, :text
      add :site_key, :text
      add :environment_key, :text
      add :text, :text, null: false, default: ""
      add :note, :text
      add :author_id, references(:users, prefix: "public", on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:ai_guidance_versions, [:scope, :inserted_at], prefix: "public")
  end
end

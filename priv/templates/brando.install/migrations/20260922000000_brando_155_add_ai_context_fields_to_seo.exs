defmodule Brando.Repo.Migrations.AddAiContextFieldsToSEO do
  use Ecto.Migration

  def change do
    alter table(:sites_seos) do
      add :ai_context_fields, :map
    end
  end
end

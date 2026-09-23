defmodule Brando.Repo.Migrations.Brando178AddSeoAiContextFields do
  use Ecto.Migration

  def change do
    alter table(:sites_seos) do
      add :ai_context_fields, :map
    end
  end
end

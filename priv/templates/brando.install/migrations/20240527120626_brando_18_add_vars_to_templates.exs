defmodule Brando.Repo.Migrations.AddVarsToTemplates do
  use Ecto.Migration

  def change do
    alter table(:pages_templates) do
      add :vars, :jsonb
    end
  end
end

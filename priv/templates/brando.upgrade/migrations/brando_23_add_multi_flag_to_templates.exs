defmodule Brando.Repo.Migrations.AddMultiFlagToTemplates do
  use Ecto.Migration

  def change do
    alter table(:pages_templates) do
      add :multi, :boolean, default: false
    end
  end
end

defmodule Brando.Repo.Migrations.AddSequenceToTemplates do
  use Ecto.Migration

  def change do
    alter table(:pages_templates) do
      add :sequence, :integer
    end
  end
end

defmodule Brando.Repo.Migrations.AddWrapperToTemplates do
  use Ecto.Migration

  def change do
    alter table(:pages_templates) do
      add :wrapper, :text
    end
  end
end

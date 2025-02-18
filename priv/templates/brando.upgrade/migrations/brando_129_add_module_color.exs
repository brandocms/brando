defmodule Brando.Repo.Migrations.AddModuleColor do
  use Ecto.Migration

  def change do
    alter table(:content_modules) do
      add :color, :string, default: "blue"
    end
  end
end

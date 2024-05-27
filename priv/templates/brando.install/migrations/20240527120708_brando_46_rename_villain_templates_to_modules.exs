defmodule Brando.Migrations.RenameTemplatesToModules do
  use Ecto.Migration

  def change do
    rename table(:pages_templates), to: table(:pages_modules)
  end
end

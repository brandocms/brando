defmodule Brando.Migrations.RenameTemplatesToModules do
  use Ecto.Migration
  import Ecto.Query

  def change do
    rename table(:pages_templates), to: table(:pages_modules)
  end
end

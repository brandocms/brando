defmodule Brando.Repo.Migrations.AddNavigationLanguageIdx do
  use Ecto.Migration

  def change do
    create_if_not_exists index(:navigation_menus, [:language])
    create_if_not_exists index(:navigation_menus, [:status])
  end
end

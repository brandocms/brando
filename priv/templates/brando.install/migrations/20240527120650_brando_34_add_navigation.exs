defmodule Brando.Migrations.AddNavigation do
  use Ecto.Migration
  use Brando.Sequence.Migration

  def change do
    create table(:navigation_menus) do
      add :status, :integer
      add :title, :text
      add :key, :text
      add :language, :text
      add :template, :text
      add :creator_id, references(:users_users)
      sequenced()
      timestamps()
    end

    create index(:navigation_menus, [:key])
    create index(:navigation_menus, [:status])

    create table(:navigation_items) do
      add :status, :integer
      add :title, :text
      add :key, :text
      add :url, :text
      add :open_in_new_window, :boolean, default: false
      add :menu_id, references(:navigation_menus, on_delete: :delete_all)
      add :parent_id, references(:navigation_items, on_delete: :delete_all)
      add :creator_id, references(:users_users)
      sequenced()
      timestamps()
    end

    create index(:navigation_items, [:key])
    create index(:navigation_items, [:status])
    create index(:navigation_items, [:menu_id])
    create index(:navigation_items, [:parent_id])
  end
end

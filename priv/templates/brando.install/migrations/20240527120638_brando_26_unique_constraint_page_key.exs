defmodule Brando.Repo.Migrations.AddUniqueConstraintPageKeys do
  use Ecto.Migration

  def change do
    drop index(:pages, [:key])
    create unique_index(:pages_pages, [:key])
  end
end

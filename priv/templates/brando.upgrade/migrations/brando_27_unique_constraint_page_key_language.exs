defmodule Brando.Repo.Migrations.AddUniqueConstraintPageKeyLanguage do
  use Ecto.Migration

  def change do
    drop index(:pages_pages, [:key])
    create unique_index(:pages_pages, [:key, :language])
  end
end

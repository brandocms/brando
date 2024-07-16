defmodule Brando.Repo.Migrations.FixPagesUniqueIndex do
  use Ecto.Migration

  def change do
    drop unique_index(:pages_pages, [:uri, :language])
    create unique_index(:pages, [:uri, :language])
  end
end

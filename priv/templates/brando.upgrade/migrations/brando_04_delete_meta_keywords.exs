defmodule Brando.Repo.Migrations.ChangeTableNames do
  use Ecto.Migration

  def change do
    alter table(:pages_pages) do
      delete(:meta_keywords)
    end
  end
end

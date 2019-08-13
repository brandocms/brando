defmodule Brando.Repo.Migrations.ChangeTableNames do
  use Ecto.Migration

  def change do
    alter table(:pages_pages) do
      remove :meta_keywords
    end
  end
end

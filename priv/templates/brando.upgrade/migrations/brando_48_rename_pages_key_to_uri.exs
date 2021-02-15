defmodule Brando.Repo.Migrations.RenamePagesKeyToUri do
  use Ecto.Migration

  def change do
    rename table(:pages_pages), :key, to: :uri

    alter table(:pages_pages) do
      remove :slug, :string, default: ""
    end
  end
end

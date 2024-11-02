defmodule Brando.Repo.Migrations.IndexCleanup do
  use Ecto.Migration

  def change do
    drop_if_exists index(:pages, [:uri], name: :pages_pages_uri_index)
    create index(:images, [:deleted_at])
    create index(:files, [:deleted_at])
    create index(:content_modules, [:deleted_at])
    create index(:content_containers, [:deleted_at])
  end
end

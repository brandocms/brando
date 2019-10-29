defmodule Brando.Repo.Migrations.DeleteLink do
  use Ecto.Migration

  def change do
    drop table(:sites_links)
  end
end

defmodule Brando.Repo.Migrations.AddIsHomepageAtToPages do
  use Ecto.Migration

  def change do
    alter table(:pages_pages) do
      add :is_homepage, :boolean, default: false
    end
  end
end

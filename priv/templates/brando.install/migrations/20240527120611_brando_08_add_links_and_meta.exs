defmodule Brando.Repo.Migrations.AddLinksAndMetaToOrganization do
  use Ecto.Migration

  def change do
    alter table(:sites_organizations) do
      add :metas, :map
      add :links, :map
    end
  end
end

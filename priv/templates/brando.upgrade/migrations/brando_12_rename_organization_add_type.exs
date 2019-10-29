defmodule Brando.Repo.Migrations.RenameOrganizationAddType do
  use Ecto.Migration

  def change do
    rename(table(:sites_organizations), to: table(:sites_identities))

    alter table(:sites_identities) do
      add :type, :string, default: "organization"
    end
  end
end

defmodule Brando.Repo.Migrations.AddTypeConfigToIdentity do
  use Ecto.Migration

  def up do
    alter table(:sites_identities) do
      add_if_not_exists :type_config, :jsonb
    end
  end

  def down do
    alter table(:sites_identities) do
      remove_if_exists :type_config, :jsonb
    end
  end
end

defmodule Brando.Repo.Migrations.AddGlobalCategoriesToIdentity do
  use Ecto.Migration

  def change do
    alter table(:sites_identities) do
      add :global_categories, :map
    end

    flush()

    execute """
    UPDATE
      sites_identities
    SET
      global_categories = jsonb_build_array(jsonb_build_object('id', 'ca199218-bc72-42ab-94e2-97d08a9b9e60', 'label', 'System', 'key', 'system', 'globals', globals))
    WHERE
      id = 1 AND global_categories IS NULL;
    """

    flush()

    alter table(:sites_identities) do
      remove :globals
    end
  end
end

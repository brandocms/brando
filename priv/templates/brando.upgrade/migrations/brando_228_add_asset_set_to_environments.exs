defmodule Brando.Repo.Migrations.Brando228AddAssetSetToEnvironments do
  use Ecto.Migration

  @moduledoc """
  An environment (`environments.asset_set_id`) may have a frontend asset set
  of its own, which its host serves and its pages render with in place of the
  site's active set. Empty for every existing environment, which keeps
  following its site's active set.
  """

  def change do
    alter table(:environments, prefix: "public") do
      # A set is protected from deletion while an environment uses it; one
      # removed anyway leaves the environment following its site's set
      add :asset_set_id, references(:site_asset_sets, prefix: "public", on_delete: :nilify_all)
    end

    create index(:environments, [:asset_set_id], prefix: "public")
  end
end

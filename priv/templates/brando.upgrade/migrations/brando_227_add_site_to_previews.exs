defmodule Brando.Repo.Migrations.Brando227AddSiteToPreviews do
  use Ecto.Migration

  @moduledoc """
  A shared preview (`sites_previews`) records the site and environment it was
  shared from. In multi-site mode a site's host opens only its own site's
  previews, and the endpoint's host opens a preview under its site.

  Fills the site of a preview shared before from its pinned asset set. A
  preview with no pinned set, or one pinned to no site's set, keeps no site
  and opens where it did before.
  """

  def up do
    alter table(:sites_previews, prefix: "public") do
      add :site_id, references(:sites, prefix: "public", on_delete: :delete_all)
      # An environment deleted before its preview expires leaves the row to
      # the purger, which releases the preview's pinned asset set
      add :environment_id, references(:environments, prefix: "public", on_delete: :nilify_all)
    end

    create index(:sites_previews, [:site_id], prefix: "public")
    create index(:sites_previews, [:environment_id], prefix: "public")

    execute """
    UPDATE public.sites_previews AS preview
    SET site_id = asset_set.site_id
    FROM public.site_asset_sets AS asset_set
    WHERE preview.asset_set_id = asset_set.id
      AND preview.site_id IS NULL
      AND asset_set.site_id IS NOT NULL
    """
  end

  def down do
    drop index(:sites_previews, [:environment_id], prefix: "public")
    drop index(:sites_previews, [:site_id], prefix: "public")

    alter table(:sites_previews, prefix: "public") do
      remove :environment_id
      remove :site_id
    end
  end
end

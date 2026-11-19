defmodule Brando.Repo.Migrations.Brando237AddAllowedDeployTargetsToSites do
  use Ecto.Migration

  @moduledoc """
  `sites.allowed_rsync_targets` and `sites.allowed_s3_targets`: the deploy
  targets a site may use besides those the installation's config lists
  (`Brando.Sites.DeployConfig`), set by a superuser. Empty for every
  existing site, which keeps the targets its config allows.
  """

  def up do
    alter table(:sites, prefix: "public") do
      add_if_not_exists :allowed_rsync_targets, {:array, :text}, null: false, default: []
      add_if_not_exists :allowed_s3_targets, {:array, :text}, null: false, default: []
    end
  end

  def down do
    alter table(:sites, prefix: "public") do
      remove_if_exists :allowed_s3_targets, {:array, :text}
      remove_if_exists :allowed_rsync_targets, {:array, :text}
    end
  end
end

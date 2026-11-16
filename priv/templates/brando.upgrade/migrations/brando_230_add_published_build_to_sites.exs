defmodule Brando.Repo.Migrations.Brando230AddPublishedBuildToSites do
  use Ecto.Migration

  @moduledoc """
  `sites.published_build`: the version of the static build the installation
  serves itself on the live environment's domain (deploy strategy `:local`),
  such as `v12`. Empty for every existing site, and for a site that deploys
  elsewhere.
  """

  def up do
    alter table(:sites, prefix: "public") do
      add_if_not_exists :published_build, :text
    end
  end

  def down do
    alter table(:sites, prefix: "public") do
      remove_if_exists :published_build, :text
    end
  end
end

defmodule Brando.Repo.Migrations.Brando226AddProviderLibraryGroupToSites do
  use Ecto.Migration

  @moduledoc """
  `sites.provider_library_group`: the sites of a multi-site installation that
  share the video providers' libraries through the picker's "Add from …"
  button. Empty, the default, keeps a site's provider videos to itself.
  """

  def up do
    alter table(:sites, prefix: "public") do
      add_if_not_exists :provider_library_group, :text
    end
  end

  def down do
    alter table(:sites, prefix: "public") do
      remove_if_exists :provider_library_group, :text
    end
  end
end

defmodule Brando.Migrations.AddAllowedDeployTargetsToSitesTest do
  use Brando.ConnCase

  import Brando.MigrationTemplates, only: [down: 2, query!: 1, rows: 2, up: 1]

  alias Brando.SiteAssetsFixtures

  @file_name "brando_237_add_allowed_deploy_targets_to_sites.exs"

  defp columns,
    do:
      rows(
        "SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'sites' AND column_name LIKE 'allowed_%' ORDER BY column_name",
        []
      )

  # A site from before the columns has only the targets config allows
  test "adds empty allowed deploy targets for every site, and rolls back" do
    {:ok, acme} = SiteAssetsFixtures.create_site("Acme", "acme", "acme.test")
    query!("ALTER TABLE public.sites DROP COLUMN allowed_rsync_targets, DROP COLUMN allowed_s3_targets")

    version = up(@file_name)

    assert rows("SELECT allowed_rsync_targets, allowed_s3_targets FROM public.sites WHERE id = $1", [acme.id]) ==
             [[[], []]]

    down(@file_name, version)

    assert columns() == []
  end
end

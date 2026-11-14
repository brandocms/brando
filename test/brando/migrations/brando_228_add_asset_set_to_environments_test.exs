defmodule Brando.Migrations.AddAssetSetToEnvironmentsTest do
  use Brando.ConnCase

  import Brando.MigrationTemplates, only: [down: 2, query!: 1, rows: 2, up: 1]

  alias Brando.SiteAssetsFixtures

  @file_name "brando_228_add_asset_set_to_environments.exs"

  # An environment from before the column follows its site's set, as it did
  test "adds an empty reference for every environment, and rolls back" do
    {:ok, acme} = SiteAssetsFixtures.create_site("Acme", "acme", "acme.test")
    query!("ALTER TABLE public.environments DROP COLUMN asset_set_id")

    version = up(@file_name)

    assert rows("SELECT asset_set_id FROM public.environments WHERE site_id = $1", [acme.id]) == [[nil]]

    down(@file_name, version)

    assert rows(
             "SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'environments' AND column_name = 'asset_set_id'",
             []
           ) == []
  end
end

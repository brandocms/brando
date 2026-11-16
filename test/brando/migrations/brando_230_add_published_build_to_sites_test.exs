defmodule Brando.Migrations.AddPublishedBuildToSitesTest do
  use Brando.ConnCase

  import Brando.MigrationTemplates, only: [down: 2, query!: 1, rows: 2, up: 1]

  alias Brando.SiteAssetsFixtures

  @file_name "brando_230_add_published_build_to_sites.exs"

  defp column?,
    do:
      rows(
        "SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'sites' AND column_name = 'published_build'",
        []
      ) != []

  # A site from before the column serves no build of its own
  test "adds an empty published build for every site, and rolls back" do
    {:ok, acme} = SiteAssetsFixtures.create_site("Acme", "acme", "acme.test")
    query!("ALTER TABLE public.sites DROP COLUMN published_build")

    version = up(@file_name)

    assert rows("SELECT published_build FROM public.sites WHERE id = $1", [acme.id]) == [[nil]]

    down(@file_name, version)

    refute column?()
  end
end

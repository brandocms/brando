defmodule Brando.Migrations.AddSiteToPreviewsTest do
  use Brando.ConnCase

  import Brando.MigrationTemplates, only: [down: 2, query!: 1, rows: 2, up: 1]

  alias Brando.SiteAssetsFixtures

  @file_name "brando_227_add_site_to_previews.exs"

  # A preview from before the columns takes its site from its pinned set
  test "fills a preview's site from its pinned set, and rolls back" do
    query!("ALTER TABLE public.sites_previews DROP COLUMN site_id, DROP COLUMN environment_id")

    {:ok, acme} = SiteAssetsFixtures.create_site("Acme", "acme", "acme.test")
    user = Brando.Factory.insert(:random_user, avatar: nil)

    acme_set = insert_set(acme.id, "acme-one")
    standalone_set = insert_set(nil, "standalone-one")
    pinned = insert_preview(user.id, acme_set)
    standalone = insert_preview(user.id, standalone_set)
    neither = insert_preview(user.id, nil)

    version = up(@file_name)

    assert site_of(pinned) == [[acme.id, nil]]
    assert site_of(standalone) == [[nil, nil]]
    assert site_of(neither) == [[nil, nil]]

    down(@file_name, version)
    assert rows("SELECT id FROM public.sites_previews WHERE id = $1", [pinned]) == [[pinned]]

    assert rows(
             "SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'sites_previews' AND column_name IN ('site_id', 'environment_id')",
             []
           ) == []
  end

  defp insert_set(site_id, name) do
    [[id]] =
      rows(
        "INSERT INTO public.site_asset_sets (site_id, name, path, uploaded_at, inserted_at, updated_at) VALUES ($1, $2, '/nowhere', NOW(), NOW(), NOW()) RETURNING id",
        [site_id, name]
      )

    id
  end

  defp insert_preview(creator_id, asset_set_id) do
    [[id]] =
      rows(
        "INSERT INTO public.sites_previews (preview_key, expires_at, html, creator_id, asset_set_id, inserted_at, updated_at) VALUES ($1, NOW() + interval '1 hour', '', $2, $3, NOW(), NOW()) RETURNING id",
        [Ecto.UUID.generate(), creator_id, asset_set_id]
      )

    id
  end

  defp site_of(id), do: rows("SELECT site_id, environment_id FROM public.sites_previews WHERE id = $1", [id])
end

defmodule Brando.Migrations.AddProposalToPreviewsTest do
  use Brando.ConnCase

  import Brando.MigrationTemplates, only: [down: 2, query!: 1, rows: 2, up: 1]

  @file_name "brando_241_add_proposal_to_previews.exs"

  defp columns,
    do:
      rows(
        "SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'sites_previews' AND column_name = 'proposal_id'",
        []
      )

  # A preview shared before keeps its row, with no proposal
  test "adds the proposal to every preview, and rolls back" do
    query!("ALTER TABLE public.sites_previews DROP COLUMN proposal_id")
    user = Brando.Factory.insert(:random_user, avatar: nil)

    [[id]] =
      rows(
        "INSERT INTO public.sites_previews (preview_key, expires_at, html, creator_id, inserted_at, updated_at) VALUES ($1, NOW() + interval '1 hour', '', $2, NOW(), NOW()) RETURNING id",
        [Ecto.UUID.generate(), user.id]
      )

    version = up(@file_name)

    assert columns() == [["proposal_id"]]
    assert rows("SELECT proposal_id FROM public.sites_previews WHERE id = $1", [id]) == [[nil]]

    down(@file_name, version)

    assert columns() == []
    assert rows("SELECT id FROM public.sites_previews WHERE id = $1", [id]) == [[id]]
  end
end

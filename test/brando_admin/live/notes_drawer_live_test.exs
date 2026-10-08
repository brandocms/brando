defmodule BrandoAdmin.NotesDrawerLiveTest do
  # A note on a block that was deleted stays in the entry's notes, marked
  # detached and no longer pointing at a block. This was part of
  # e2e/playwright/tests/blocks/block-notes.spec.js; the drawer is
  # server-rendered. Placing notes and the per-block counts stay there.
  use Brando.LiveCase

  alias Brando.Notes
  alias Brando.Pages.Page

  test "a note whose block is gone is shown detached, without a link to the block", %{conn: conn, current_user: user} do
    page = Factory.insert(:page, creator: user)
    {:ok, note, _} = Notes.create_thread(Page, page.id, user, %{"body" => "Keep this heading", "block_uid" => "gone"})
    :ok = Notes.entry_saved(Page, page)
    assert Repo.get!(Brando.Notes.Note, note.id).detached_at

    {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
    thread = await_selector(view, ".note-state.is-detached")

    [anchor] =
      thread
      |> Floki.parse_document!()
      |> Floki.find(".note-anchor:has(.note-state.is-detached) .note-anchor-link")

    assert Floki.attribute(anchor, "data-block-uid") == []
  end
end

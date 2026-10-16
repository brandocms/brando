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

  test "a thread id that is not a whole integer is ignored", %{conn: conn, current_user: user} do
    page = Factory.insert(:page, creator: user)
    {:ok, thread, _} = Notes.create_thread(Page, page.id, user, %{"body" => "Check the intro"})
    {:ok, _reply, _} = Notes.reply(thread, user, %{"body" => "Done"})
    {:ok, _} = Notes.resolve(Repo.get!(Brando.Notes.Note, thread.id), user)

    {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
    drawer = with_target(view, "#page_form-notes")
    render_click(drawer, "tab", %{"tab" => "resolved"})
    toggle = "#page_form-notes .note-toggle[phx-value-id='#{thread.id}']"
    assert has_element?(view, toggle <> "[aria-expanded='false']")

    for id <- ["abc", "#{thread.id}abc", "1.5", ""] do
      render_click(drawer, "toggle_thread", %{"id" => id})
      render_click(drawer, "reopen", %{"id" => id})
      render_click(drawer, "reply", %{"thread" => id, "reply" => %{"body" => "Lost"}})
    end

    assert has_element?(view, toggle <> "[aria-expanded='false']")
    assert Repo.get!(Brando.Notes.Note, thread.id).resolved_at

    render_click(drawer, "toggle_thread", %{"id" => to_string(thread.id)})
    assert has_element?(view, toggle <> "[aria-expanded='true']")
  end
end

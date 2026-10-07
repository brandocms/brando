defmodule BrandoAdmin.EditSessionSavesTest do
  # Saves, outside writes and recovery copies with two editors in one entry's
  # edit session, through real LiveViews. Each test is a case a review found
  # losing or corrupting work (#2992).
  use Brando.LiveCase

  import Brando.EditSessionEditors
  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.DeleteBlock
  alias Brando.EditSession
  alias Brando.Pages.Page
  alias BrandoAdmin.Components.Form.BlockField

  @block_field "page_form-blocks-blocks"

  setup do
    c = Brando.ProposalFixtures.context()
    other = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
    other_conn = log_in_user(Phoenix.ConnTest.build_conn(), other)
    uids = c.identity |> rows() |> Enum.map(& &1.block.uid)
    Map.merge(c, %{other: other, other_conn: other_conn, uids: uids})
  end

  defp texts(page), do: Enum.map(rows(page), &{&1.block.uid, hd(&1.block.refs).data.data.text})

  defp open(conn, page) do
    {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
    await_selector(view, "[data-block-uid]")
    view
  end

  # A save is two submits: the first collects the blocks (the session's
  # state is read here), the second writes.
  defp save_read(view) do
    view |> form("#page_form_form") |> render_submit()
    assert_push_event(view, "b:submit", %{}, 2_000)
  end

  defp save_write(view), do: view |> form("#page_form_form") |> render_submit()

  # "Save and continue editing": the editor stays open after the save.
  defp stay(view) do
    cid =
      view
      |> render()
      |> Floki.parse_document!()
      |> Floki.find("[data-phx-component]")
      |> Enum.filter(&(Floki.find(&1, "#page_form-el") != []))
      |> Enum.map(&(&1 |> Floki.attribute("data-phx-component") |> hd() |> String.to_integer()))
      |> Enum.max()

    view |> with_target(cid) |> render_hook("save_redirect_target", %{})
  end

  defp insert_block(view, c, sequence) do
    Phoenix.LiveView.send_update(view.pid, BlockField,
      id: @block_field,
      event: "insert_block",
      sequence: sequence,
      module_id: c.text_module.id
    )
  end

  defp new_uid(view, known) do
    ~r/data-block-uid="([^"]+)"/
    |> Regex.scan(render(view))
    |> Enum.map(&List.last/1)
    |> Enum.uniq()
    |> Kernel.--(known)
    |> List.first()
  end

  defp added_block(a, b, c) do
    insert_block(a, c, 0)
    await(fn -> new_uid(a, c.uids) != nil end)
    uid = new_uid(a, c.uids)
    await(fn -> render(b) =~ ~s(data-block-uid="#{uid}") end)
    uid
  end

  defp block_count(uid), do: Repo.one(from(b in Brando.Content.Block, where: b.uid == ^uid, select: count(b.id)))

  defp session_state(page) do
    {:ok, %{state: state}} =
      EditSession.fetch(EditSession.whereis(EditSession.ref(Page, page.id, page.language)), :blocks)

    state
  end

  # #2: save and close used to leave the session without the rebase, so
  # the other editor's session kept the new block as unsaved and every later
  # save of theirs failed with "uid has already been taken".
  test "after a save that closes the editor, the other editor can still save", c do
    [first | _] = c.uids
    a = open(c.conn, c.identity)
    b = open(c.other_conn, c.identity)
    new = added_block(a, b, c)

    save_read(a)
    save_write(a)
    assert_redirect(a, 3_000)

    await(fn -> session_state(c.identity).statuses[new] == :persisted end)
    type(b, first, "<p>B, after A closed</p>")
    stay(b)
    save_read(b)
    save_write(b)

    await(fn -> Map.new(texts(c.identity))[first] == "<p>B, after A closed</p>" end)
    assert block_count(new) == 1
    assert length(rows(c.identity)) == 4
  end

  # #11: two saves at once with a new block. The second write inserts the
  # block again and is refused; once the first save's rebase has arrived, a
  # retry goes through.
  test "of two overlapping saves the second can be retried, without a duplicate block", c do
    a = open(c.conn, c.identity)
    b = open(c.other_conn, c.identity)
    new = added_block(a, b, c)
    stay(a)
    stay(b)

    save_read(a)
    save_read(b)
    save_write(a)
    await(fn -> session_state(c.identity).statuses[new] == :persisted end)
    save_write(b)
    assert block_count(new) == 1

    type(b, new, "<p>B retries</p>")
    save_read(b)
    save_write(b)

    await(fn -> Map.new(texts(c.identity))[new] == "<p>B retries</p>" end)
    assert block_count(new) == 1
    assert length(rows(c.identity)) == 4
  end

  # A keystroke on a block that was new when a save read the state, landing
  # before the save's rebase: it is replayed onto the saved rows, and later
  # saves keep working.
  test "typing in a new block while another editor's save runs is kept, and saves after it work", c do
    a = open(c.conn, c.identity)
    b = open(c.other_conn, c.identity)
    new = added_block(a, b, c)
    stay(a)

    type(b, new, "<p>B first</p>")
    await(fn -> shown_text(a, new) == "<p>B first</p>" end)

    save_read(a)
    type(b, new, "<p>B typed during A's save</p>")
    save_write(a)
    await(fn -> session_state(c.identity).statuses[new] == :persisted end)

    assert session_state(c.identity).diffs[new] != nil
    type(b, new, "<p>B after the save</p>")
    stay(b)
    save_read(b)
    save_write(b)

    await(fn -> Map.new(texts(c.identity))[new] == "<p>B after the save</p>" end)
    assert block_count(new) == 1
    [row] = Enum.filter(rows(c.identity), &(&1.block.uid == new))
    assert length(row.block.refs) == 1
  end

  test "an editor who types in a new block during their own save, then saves again, keeps it all", c do
    a = open(c.conn, c.identity)
    stay(a)
    insert_block(a, c, 0)
    await(fn -> new_uid(a, c.uids) != nil end)
    new = new_uid(a, c.uids)

    type(a, new, "<p>first</p>")
    save_read(a)
    type(a, new, "<p>typed while saving</p>")
    save_write(a)
    await(fn -> session_state(c.identity).statuses[new] == :persisted end)

    stay(a)
    save_read(a)
    save_write(a)
    await(fn -> Map.new(texts(c.identity))[new] == "<p>typed while saving</p>" end)
    assert Process.alive?(a.pid)
    assert block_count(new) == 1
  end

  # #4: applying a recovery copy replaced the whole field and wiped the
  # other editor's unsaved work.
  test "applying a recovery copy keeps another editor's unsaved work", c do
    [first, second | _] = c.uids
    a = open(c.conn, c.identity)
    b = open(c.other_conn, c.identity)
    type(b, second, "<p>B, unsaved</p>")
    await(fn -> shown_text(a, second) == "<p>B, unsaved</p>" end)

    # A's recovery copy changes the first block.
    originals = rows(c.identity)

    changesets =
      Enum.map(originals, fn row ->
        params =
          if row.block.uid == first do
            %{
              "block" => %{
                "id" => row.block.id,
                "refs" => [
                  %{
                    "id" => hd(row.block.refs).id,
                    "data" => %{"type" => "text", "data" => %{"text" => "<p>From the copy</p>"}}
                  }
                ]
              }
            }
          else
            %{}
          end

        Page.Blocks.changeset(row, params, c.user.id, true)
      end)

    Phoenix.LiveView.send_update(a.pid, BlockField,
      id: @block_field,
      event: "restore_draft",
      changesets: changesets,
      entry_blocks: originals
    )

    await(fn -> shown_text(a, first) == "<p>From the copy</p>" end)
    await(fn -> shown_text(b, first) == "<p>From the copy</p>" end)
    assert shown_text(a, second) == "<p>B, unsaved</p>"
    assert shown_text(b, second) == "<p>B, unsaved</p>"
    state = session_state(c.identity)
    assert state.diffs[second] != nil and state.diffs[first] != nil
  end

  # #5: unsaved work on a block another writer deleted was announced as
  # "kept in your recovery copy", which it was not. It comes back as a new
  # block instead.
  test "a block someone else deletes comes back, as new, for the editor with unsaved work in it", c do
    [_first, second | _] = c.uids
    b = open(c.other_conn, c.identity)
    type(b, second, "<p>B's unsaved work</p>")

    {:ok, proposal} = Proposals.propose([%DeleteBlock{target: {Page, c.identity.id}, block_uid: second}], c.user)
    {:ok, _} = Proposals.approve(proposal.id, proposal.version, c.user)
    {:ok, _} = Proposals.apply(proposal.id, proposal.version, c.user)

    kept = second <> "-kept"
    await(fn -> session_state(c.identity).statuses[kept] == :inserted end)
    await(fn -> shown_text(b, kept) == "<p>B's unsaved work</p>" end)

    stay(b)
    save_read(b)
    save_write(b)
    await(fn -> Map.new(texts(c.identity))[kept] == "<p>B's unsaved work</p>" end)
    refute Map.has_key?(Map.new(texts(c.identity)), second)
    assert length(rows(c.identity)) == 3
  end

  # #5: a change to a block another editor had just deleted was rejected by
  # the session without a word to the editor who made it.
  test "a change to a block another editor just deleted is reported to its author", c do
    [_first, second | _] = c.uids
    a = open(c.conn, c.identity)
    b = open(c.other_conn, c.identity)
    Brando.endpoint().subscribe("user:#{c.other.id}")
    session = EditSession.whereis(EditSession.ref(Page, c.identity.id, c.identity.language))

    # Both changes reach the session before it applies either: A's delete
    # first, then B's typing in the block B still shows.
    :sys.suspend(session)
    Phoenix.LiveView.send_update(a.pid, BlockField, id: @block_field, event: "delete_block", uid: second)
    render(a)
    type(b, second, "<p>Too late</p>")
    :sys.resume(session)

    assert_receive %Phoenix.Socket.Broadcast{event: "toast"}, 2_000
    await(fn -> not (render(b) =~ ~s(data-block-uid="#{second}")) end)
  end

  # #10: refreshing a root for another editor's change also rewrote its seed
  # form, so the field re-rendered and the block was updated a second time.
  test "another editor's change updates only the block it changed", c do
    [first | _] = c.uids
    a = open(c.conn, c.identity)
    b = open(c.other_conn, c.identity)
    test = self()
    handler = "block-updates-#{System.unique_integer()}"
    a_pid = a.pid

    :telemetry.attach(
      handler,
      [:phoenix, :live_component, :update, :stop],
      fn _event, _measurements, %{component: component, assigns_sockets: assigns_sockets}, _ ->
        if self() == a_pid and component == BrandoAdmin.Components.Form.Block,
          do: send(test, {:block_updates, Enum.map(assigns_sockets, fn {_, socket} -> socket.assigns[:uid] end)})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    type(b, first, "<p>One block changes</p>")
    await(fn -> shown_text(a, first) == "<p>One block changes</p>" end)
    Process.sleep(200)

    updated = collect_block_updates([])
    # Once: the replaced form. Writing the root's seed form as well re-rendered
    # the block a second time, through the field.
    assert updated == [first]
  end

  defp collect_block_updates(acc) do
    receive do
      {:block_updates, uids} -> collect_block_updates(acc ++ uids)
    after
      0 -> acc
    end
  end

  # #9: activating a revision outside the drawer (a scheduled activation)
  # wrote the entry without telling the open editors.
  test "activating a revision moves open editors onto it, keeping their unsaved work", c do
    [first, second | _] = c.uids
    entry = Page |> Repo.get!(c.identity.id) |> Repo.preload(Brando.Blueprint.preloads_for(Page))
    {:ok, _} = Brando.Revisions.create_revision(entry, c.user)

    # The entry is changed and saved after the revision was taken…
    a = open(c.conn, c.identity)
    stay(a)
    type(a, first, "<p>Saved by A</p>")
    save_read(a)
    save_write(a)
    await(fn -> Map.new(texts(c.identity))[first] == "<p>Saved by A</p>" end)

    # …B has unsaved work in another block when the revision comes back.
    b = open(c.other_conn, c.identity)
    assert shown_text(b, first) == "<p>Saved by A</p>"
    type(b, second, "<p>B, unsaved</p>")

    {:ok, _} = Brando.Revisions.set_entry_to_revision(Page, c.identity.id, 0, c.user)

    await(fn -> shown_text(b, first) == "<p>Identity 0</p>" end)
    assert shown_text(b, second) == "<p>B, unsaved</p>"
  end
end

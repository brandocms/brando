defmodule BrandoAdmin.EditSessionSavesTest do
  # Saves, outside writes and recovery copies with two editors in one entry's
  # edit session, through real LiveViews. Each test is a case a review found
  # losing or corrupting work (#2992).
  use Brando.LiveCase

  import Brando.EditSessionEditors
  import Ecto.Query, only: [from: 2, where: 3]

  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.DeleteBlock
  alias Brando.Content.Proposals.InsertBlock
  alias Brando.EditSession
  alias Brando.Pages.Page
  alias BrandoAdmin.Components.Form.BlockField
  alias BrandoAdmin.Components.Form.BlockField.Ops

  @block_field "page_form-blocks-blocks"

  setup %{current_user: me} do
    c = Brando.ProposalFixtures.context()
    other = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
    other_conn = log_in_user(Phoenix.ConnTest.build_conn(), other)
    uids = c.identity |> rows() |> Enum.map(& &1.block.uid)
    Map.merge(c, %{me: me, other: other, other_conn: other_conn, uids: uids})
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
    assert_push_event(view, "b:submit", %{}, 5_000)
  end

  defp save_write(view), do: view |> form("#page_form_form") |> render_submit()

  # "Save and continue editing": the editor stays open after the save.
  defp stay(view), do: view |> with_target(form_cid(view)) |> render_hook("save_redirect_target", %{})

  # The Form component's id, to send it the events its buttons send.
  defp form_cid(view), do: cid_of(view, "#page_form-el")

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

  defp session_pid(page), do: EditSession.whereis(EditSession.ref(Page, page.id, page.language))

  defp session_state(page) do
    {:ok, %{state: state}} = EditSession.fetch(session_pid(page), :blocks)
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

    await(fn -> shows_saved?(b, new) end)
    assert session_state(c.identity).statuses[new] == :persisted
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
    # B writes after A's write and before A's rebase reaches it: the session
    # takes the rebase only once B's write is done.
    session = session_pid(c.identity)
    :sys.suspend(session)

    try do
      save_write(a)
      save_write(b)
    after
      :sys.resume(session)
    end

    assert block_count(new) == 1

    await(fn -> shows_saved?(b, new) end)
    type(b, new, "<p>B retries</p>")
    save_read(b)
    save_write(b)

    await(fn -> Map.new(texts(c.identity))[new] == "<p>B retries</p>" end)
    assert block_count(new) == 1
    assert length(rows(c.identity)) == 4
  end

  # The other order: A's rebase reaches B between its collect and its write.
  # The write the first submit asked for collects the blocks again, from the
  # saved rows, instead of inserting the new block a second time.
  test "of two overlapping saves the second collects again when the first's rebase arrives before it writes", c do
    a = open(c.conn, c.identity)
    b = open(c.other_conn, c.identity)
    new = added_block(a, b, c)
    stay(a)
    stay(b)

    save_read(a)
    type(b, new, "<p>B, after A read</p>")
    save_read(b)
    save_write(a)
    await(fn -> shows_saved?(b, new) end)
    save_read(b)
    save_write(b)

    await(fn -> Map.new(texts(c.identity))[new] == "<p>B, after A read</p>" end)
    assert block_count(new) == 1
    assert length(rows(c.identity)) == 4
  end

  # The save button and ⌘S push the form's fields (`save_form`) instead of
  # submitting the form, so the focused input keeps typing during a save.
  test "a save pushed as form fields saves like a submit", c do
    [first | _] = c.uids
    a = open(c.conn, c.identity)
    stay(a)
    type(a, first, "<p>Saved by a pushed save</p>")
    form = a |> render() |> form_params("#page_form_form") |> put_in(["page", "title"], "Pushed")
    cid = form_cid(a)

    a |> with_target(cid) |> render_hook("save_form", %{"form" => Plug.Conn.Query.encode(form)})
    assert_push_event(a, "b:submit", %{}, 2_000)
    a |> with_target(cid) |> render_hook("save_form", %{"form" => Plug.Conn.Query.encode(form)})

    await(fn -> Repo.get!(Page, c.identity.id).title == "Pushed" end)
    assert Map.new(texts(c.identity))[first] == "<p>Saved by a pushed save</p>"
  end

  # Follow-up, round 2: a save whose new URL opens the redirect prompt left
  # the edit session on the old rows, its mark pinning the op log, until the
  # prompt was answered.
  test "a save that asks about a redirect moves the session on at once", c do
    [first | _] = c.uids
    a = open(c.conn, c.identity)
    b = open(c.other_conn, c.identity)
    stay(a)
    type(a, first, "<p>Saved with a new URL</p>")
    a |> form("#page_form_form") |> render_change(%{"page" => %{"uri" => "moved-on"}, "_target" => ["page", "uri"]})
    save_read(a)
    save_write(a)
    assert render(a) =~ "moved-on"

    session = EditSession.whereis(EditSession.ref(Page, c.identity.id, c.identity.language))
    await(fn -> :sys.get_state(session).data.fields[:blocks].marks == %{} end)
    assert session_state(c.identity).diffs[first] in [nil, %{}]
    assert shown_text(b, first) == "<p>Saved with a new URL</p>"
  end

  # Follow-up, round 2: the save button and then ⌘S (or ⌘S twice) before
  # the first answered wrote the entry twice.
  test "two quick saves write once", c do
    [first | _] = c.uids
    a = open(c.conn, c.identity)
    stay(a)
    type(a, first, "<p>Saved once</p>")
    cid = form_cid(a)
    form = a |> render() |> form_params("#page_form_form") |> Plug.Conn.Query.encode()

    revisions = fn ->
      Repo.one(from(r in Brando.Revisions.Revision, where: r.entry_id == ^c.identity.id, select: count()))
    end

    before = revisions.()
    a |> with_target(cid) |> render_hook("save_form", %{"form" => form})
    a |> with_target(cid) |> render_hook("save_form", %{"form" => form})

    # every b:submit is answered, as the browser does, with its token
    answered =
      Enum.reduce_while(1..4, 0, fn _, answered ->
        receive do
          {ref, {:push_event, "b:submit", %{token: token}}} when is_reference(ref) ->
            a |> with_target(cid) |> render_hook("save_form", %{"form" => form, "token" => token})
            {:cont, answered + 1}
        after
          1_000 -> {:halt, answered}
        end
      end)

    assert answered == 1
    assert revisions.() - before == 1
    assert Map.new(texts(c.identity))[first] == "<p>Saved once</p>"

    # a b:submit answered after its save wrote is ignored
    a |> with_target(cid) |> render_hook("save_form", %{"form" => form, "token" => 12_345})
    refute_receive {_, {:push_event, "b:submit", _}}, 300
    assert revisions.() - before == 1
  end

  # Follow-up: a save's mark is cleared when the save is done, not after a
  # fixed time. A save that fails lets go of it at once.
  test "a save that fails lets the session forget what it read", c do
    a = open(c.conn, c.identity)
    stay(a)
    session = EditSession.whereis(EditSession.ref(Page, c.identity.id, c.identity.language))
    marked? = fn -> Map.has_key?(:sys.get_state(session).data.fields[:blocks].marks, a.pid) end

    a |> form("#page_form_form") |> render_change(%{"page" => %{"title" => ""}, "_target" => ["page", "title"]})
    save_read(a)
    assert marked?.()
    save_write(a)
    await(fn -> not marked?.() end)
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
    await(fn -> shows_saved?(b, new) end)

    assert session_state(c.identity).statuses[new] == :persisted
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

  # #1 (field ops): the same with a save that closes the editor. B's ops on
  # the new block, replayed onto the saved rows, named its ref by uid; the
  # next keystroke named it by id, and B's save inserted a second, nameless
  # ref.
  test "typing in a new block while another editor saves and closes, then saving, keeps one ref", c do
    a = open(c.conn, c.identity)
    b = open(c.other_conn, c.identity)
    new = added_block(a, b, c)

    type(b, new, "<p>B first</p>")
    await(fn -> shown_text(a, new) == "<p>B first</p>" end)

    save_read(a)
    type(b, new, "<p>B typed during A's save</p>")
    # the keystroke reaches the session before A's save writes
    await(fn -> inspect(session_state(c.identity).diffs[new]) =~ "during A's save" end)
    save_write(a)

    # B's form has the saved rows' ids: its next keystroke names the ref by
    # id, where the replayed one named it by uid
    await(fn ->
      ref_id =
        b |> render() |> form_params("#entry_block_form-#{new}") |> get_in(["entry_block", "block", "refs", "0", "id"])

      ref_id not in [nil, ""]
    end)

    type(b, new, "<p>B after the save</p>")
    save_read(b)
    save_write(b)
    await(fn -> Map.new(texts(c.identity))[new] == "<p>B after the save</p>" end)

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

  # Review: an editor coming back to a session that moved onto other rows
  # reads its rows again before it builds the copy of a removed block it
  # worked in. Built over the new rows, which lack the block, the copy lost
  # what the editor had not changed in it (its ref's name).
  test "a block removed while the session was away comes back whole for the editor with unsaved work in it", c do
    [_first, second | _] = c.uids
    [ref] = c.identity |> rows() |> Enum.find(&(&1.block.uid == second)) |> then(& &1.block.refs)
    b = open(c.other_conn, c.identity)
    type(b, second, "<p>B's unsaved work</p>")
    await(fn -> session_state(c.identity).diffs[second] not in [nil, %{}] end)

    # B handles the session's exit late: the block goes, and a fresh editor
    # seeds the new session from the rows without it, first.
    :sys.suspend(b.pid)
    old = session_pid(c.identity)
    Process.exit(old, :kill)
    await(fn -> session_pid(c.identity) != old end)

    {:ok, proposal} = Proposals.propose([%DeleteBlock{target: {Page, c.identity.id}, block_uid: second}], c.user)
    {:ok, _} = Proposals.approve(proposal.id, proposal.version, c.user)
    {:ok, _} = Proposals.apply(proposal.id, proposal.version, c.user)

    _a = open(c.conn, c.identity)
    :sys.resume(b.pid)

    kept = second <> "-kept"
    await(fn -> session_state(c.identity).statuses[kept] == :inserted end)
    await(fn -> shown_text(b, kept) == "<p>B's unsaved work</p>" end)
    assert [%{"name" => name}] = session_state(c.identity).diffs[kept]["block"]["refs"]
    assert name == ref.name
  end

  # A ref added to a block in the database, as a save the session never
  # heard of would: the block's rows change, its structure does not.
  defp add_ref_row(page, uid) do
    row = page |> rows() |> Enum.find(&(&1.block.uid == uid))

    Repo.insert!(%Brando.Content.Ref{
      block_id: row.block.id,
      name: "extra",
      uid: Brando.Utils.generate_uid(),
      sequence: 1,
      data: %Brando.Villain.Blocks.TextBlock{data: %Brando.Villain.Blocks.TextBlock.Data{text: "<p>Extra</p>"}}
    })
  end

  defp shown_refs(view, uid) do
    view
    |> render()
    |> Brando.LiveCase.form_params("#entry_block_form-#{uid}")
    |> get_in(["entry_block", "block", "refs"])
    |> Map.new()
    |> map_size()
  end

  # Review: a joiner with newer rows moved the session onto them, but the
  # others took it as a plain join, compared blocks alone and kept showing
  # (and later seeding and saving) the rows without the new one.
  test "editors read the rows again when a joiner moves the session onto newer rows", c do
    [first | _] = c.uids
    a = open(c.conn, c.identity)
    assert shown_refs(a, first) == 1

    add_ref_row(c.identity, first)
    _c = open(c.other_conn, c.identity)

    await(fn -> shown_refs(a, first) == 2 end)
  end

  # Review: an editor that came back with older rows read them again, but
  # kept showing its blocks' forms from the rows it had first.
  test "an editor that rejoins with older rows shows the rows it read again", c do
    [first | _] = c.uids
    a = open(c.conn, c.identity)
    b = open(c.other_conn, c.identity)
    assert shown_refs(b, first) == 1

    :sys.suspend(b.pid)
    old = session_pid(c.identity)
    Process.exit(old, :kill)
    # A comes back first and seeds the new session with the rows it has
    await(fn -> session_pid(c.identity) not in [nil, old] end)
    await(fn -> shown_text(a, first) != nil end)

    add_ref_row(c.identity, first)
    _c = open(c.conn, c.identity)
    await(fn -> shown_refs(a, first) == 2 end)

    :sys.resume(b.pid)
    await(fn -> shown_refs(b, first) == 2 end)
  end

  # Two editors held the same new block when the session died. The one who
  # came back second had changed it (its op never reached the session):
  # the session keeps the first's version, and the second's comes back as
  # a copy beside it.
  test "a new block both editors held comes back as a copy for the one whose version the session did not keep", c do
    a = open(c.conn, c.identity)
    b = open(c.other_conn, c.identity)
    uid = added_block(a, b, c)

    old = session_pid(c.identity)
    :sys.suspend(old)
    type(b, uid, "<p>B's version</p>")
    :sys.suspend(b.pid)
    Process.exit(old, :kill)
    # A comes back first and seeds the new session with its version
    await(fn -> session_pid(c.identity) not in [nil, old] end)
    :sys.resume(b.pid)

    kept = uid <> "-kept"
    await(fn -> session_state(c.identity).statuses[kept] == :inserted end)
    state = session_state(c.identity)
    assert Enum.find_index(state.order, &(&1 == kept)) == Enum.find_index(state.order, &(&1 == uid)) + 1
    await(fn -> shown_text(b, kept) == "<p>B's version</p>" end)
    await(fn -> shown_text(a, kept) == "<p>B's version</p>" end)
    refute shown_text(a, uid) == "<p>B's version</p>"
    refute state.diffs[kept]["block"]["sync_uid"] == uid
  end

  # Sol audit: copies placed by positions read before any went in landed
  # before the second original.
  test "copies of two new blocks each come right after their own", c do
    a = open(c.conn, c.identity)
    b = open(c.other_conn, c.identity)
    first = added_block(a, b, c)
    second = added_block(a, b, %{c | uids: [first | c.uids]})

    old = session_pid(c.identity)
    :sys.suspend(old)
    type(b, first, "<p>B's first</p>")
    type(b, second, "<p>B's second</p>")
    :sys.suspend(b.pid)
    Process.exit(old, :kill)
    await(fn -> session_pid(c.identity) not in [nil, old] end)
    :sys.resume(b.pid)

    await(fn -> Enum.all?([first, second], &(session_state(c.identity).statuses[&1 <> "-kept"] == :inserted)) end)
    order = session_state(c.identity).order

    for uid <- [first, second] do
      assert Enum.find_index(order, &(&1 == uid <> "-kept")) == Enum.find_index(order, &(&1 == uid)) + 1
    end
  end

  test "a new block both editors held in the same version is not copied when one rejoins", c do
    a = open(c.conn, c.identity)
    b = open(c.other_conn, c.identity)
    uid = added_block(a, b, c)
    type(b, uid, "<p>Seen by both</p>")
    await(fn -> shown_text(a, uid) == "<p>Seen by both</p>" end)

    old = session_pid(c.identity)
    :sys.suspend(b.pid)
    Process.exit(old, :kill)
    await(fn -> session_pid(c.identity) not in [nil, old] end)
    :sys.resume(b.pid)

    await(fn ->
      MapSet.size(
        EditSession.whereis(EditSession.ref(Page, c.identity.id, c.identity.language))
        |> :sys.get_state()
        |> Map.get(:clients)
        |> Map.keys()
        |> MapSet.new()
      ) == 2
    end)

    refute Map.has_key?(session_state(c.identity).statuses, uid <> "-kept")
    assert shown_text(b, uid) == "<p>Seen by both</p>"
  end

  # Review of #3055: the block came back after its rescue (the proposal was
  # undone) while the first copy stayed, and work in it was then removed
  # again. The first copy settled the second rescue, so nothing was
  # inserted and the new work was lost.
  test "a block removed again while its first copy is still there comes back as a second copy", c do
    [_first, second | _] = c.uids
    b = open(c.other_conn, c.identity)
    type(b, second, "<p>First work</p>")

    {:ok, proposal} = Proposals.propose([%DeleteBlock{target: {Page, c.identity.id}, block_uid: second}], c.user)
    {:ok, _} = Proposals.approve(proposal.id, proposal.version, c.user)
    {:ok, _} = Proposals.apply(proposal.id, proposal.version, c.user)
    await(fn -> shown_text(b, second <> "-kept") == "<p>First work</p>" end)

    {:ok, _} = Proposals.undo(proposal.id, c.user)
    await(fn -> Ops.known?(session_state(c.identity), second) end)
    # The session has the block back before B's replica renders it.
    await(fn -> render(b) =~ ~s(id="entry_block_form-#{second}") end)
    type(b, second, "<p>Second work</p>")

    {:ok, again} = Proposals.propose([%DeleteBlock{target: {Page, c.identity.id}, block_uid: second}], c.user)
    {:ok, _} = Proposals.approve(again.id, again.version, c.user)
    {:ok, _} = Proposals.apply(again.id, again.version, c.user)

    await(fn -> shown_text(b, second <> "-kept-2") == "<p>Second work</p>" end)
    assert shown_text(b, second <> "-kept") == "<p>First work</p>"
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

  # Round 3 #3: a container with a child added in it, removed by an outside
  # write. The child was brought back on its own first, then registered as
  # the existing child of the container brought back after it, which
  # overwrote its content and left the container without it. Every `"uid"`
  # in the params was renamed, those inside ref data too.
  test "a removed container with a new child comes back whole, its refs' data untouched", c do
    c = Brando.ProposalFixtures.multi_context(c)
    b = open(c.other_conn, c.work)

    Phoenix.LiveView.send_update(b.pid, BrandoAdmin.Components.Form.Block,
      id: "block-#{c.multi_uid}",
      event: "insert_block",
      sequence: 3,
      module_id: c.project_module.id,
      type: :module_entry
    )

    await(fn -> length(session_state(c.work).child_order[c.multi_uid] || []) == 4 end)
    [child] = session_state(c.work).child_order[c.multi_uid] -- c.child_uids
    refs = session_state(c.work).diffs[child]["refs"]

    {:ok, proposal} = Proposals.propose([%DeleteBlock{target: {Page, c.work.id}, block_uid: c.multi_uid}], c.user)
    {:ok, _} = Proposals.approve(proposal.id, proposal.version, c.user)
    {:ok, _} = Proposals.apply(proposal.id, proposal.version, c.user)

    kept = c.multi_uid <> "-kept"
    await(fn -> session_state(c.work).statuses[kept] == :inserted end)
    state = session_state(c.work)

    # one block back, the container, holding its children and the new one
    assert state.order -- [c.intro_uid] == [kept]
    assert state.child_order[kept] == Enum.map(c.child_uids ++ [child], &(&1 <> "-kept"))
    kept_child = state.diffs[child <> "-kept"]
    assert kept_child["module_id"] == c.project_module.id
    # the refs are new rows (their uids are unique), with the same data
    texts = &Enum.map(&1, fn ref -> {ref["name"], get_in(ref, ["data", "data", "text"])} end)
    assert texts.(kept_child["refs"]) == texts.(refs)
    assert Enum.all?(kept_child["refs"], &(&1["uid"] not in Enum.map(refs, fn ref -> ref["uid"] end)))
  end

  # Round 3: activating a revision from one's own drawer, with unsaved work
  # in a block the revision lacks. The write came from the editor's own
  # process, which was never asked to bring the work back: it was lost
  # without a word.
  test "work in a block an activated revision lacks comes back for the editor who activated it", c do
    entry = Page |> Repo.get!(c.identity.id) |> Repo.preload(Brando.Blueprint.preloads_for(Page))
    {:ok, _} = Brando.Revisions.create_revision(entry, c.user)
    revision = revisions(c.identity)

    # a block the revision does not have, saved, then changed and not saved
    a = open(c.conn, c.identity)
    stay(a)
    insert_block(a, c, 0)
    await(fn -> new_uid(a, c.uids) != nil end)
    new = new_uid(a, c.uids)
    save_read(a)
    save_write(a)
    await(fn -> block_count(new) == 1 and session_state(c.identity).statuses[new] == :persisted end)
    type(a, new, "<p>Unsaved, in a block the revision lacks</p>")
    await(fn -> session_state(c.identity).diffs[new] not in [nil, %{}] end)

    Brando.endpoint().subscribe("user:#{c.me.id}")
    drawer = cid_of(a, "#page_form-revisions-drawer-tab-activity")
    a |> with_target(drawer) |> render_hook("activate_revision", %{"value" => revision})

    kept = new <> "-kept"
    await(fn -> session_state(c.identity).statuses[kept] == :inserted end, 300)
    assert_receive %Phoenix.Socket.Broadcast{event: "toast"}, 2_000
  end

  # Follow-up, round 2: two editors' work in two children of one removed
  # container. Each brought back its own copy of the container under one
  # uid, and the session turned the second away: one editor's work was lost.
  test "work two editors had in two children of a removed container comes back in one copy", c do
    c = Brando.ProposalFixtures.multi_context(c)
    [x, y | _] = c.child_uids
    a = open(c.conn, c.work)
    b = open(c.other_conn, c.work)
    Brando.endpoint().subscribe("user:#{c.me.id}")
    Brando.endpoint().subscribe("user:#{c.other.id}")

    set_child(a, x, ["child_block", "refs", "0", "data", "data", "text"], "<p>A's child work</p>")
    set_child(b, y, ["child_block", "refs", "0", "data", "data", "text"], "<p>B's child work</p>")
    await(fn -> session_state(c.work).diffs[x] != nil and session_state(c.work).diffs[y] != nil end)
    delete_outside(c, c.multi_uid)

    shell = c.multi_uid <> "-kept"
    await(fn -> session_state(c.work).statuses[shell] == :inserted end)
    state = session_state(c.work)
    assert state.order == [c.intro_uid, shell]
    assert state.child_order[shell] == [x <> "-kept", y <> "-kept"]
    assert kept_text(state, x <> "-kept") == "<p>A's child work</p>"
    assert kept_text(state, y <> "-kept") == "<p>B's child work</p>"

    # each of them is told their work is back
    assert_receive %Phoenix.Socket.Broadcast{topic: "user:" <> a_id, event: "toast"}, 2_000
    assert_receive %Phoenix.Socket.Broadcast{topic: "user:" <> b_id, event: "toast"}, 2_000
    assert Enum.sort([a_id, b_id]) == Enum.sort([to_string(c.me.id), to_string(c.other.id)])
  end

  # Follow-up: the editor whose unsaved work a removed block held had left,
  # and nobody brought it back. An editor still here does now, and every
  # editor still here is told.
  test "work an editor who has left had in a removed block comes back, and the others hear of it", c do
    [_first, second | _] = c.uids
    a = open(c.conn, c.identity)
    b = open(c.other_conn, c.identity)
    type(b, second, "<p>B's work, B gone</p>")
    await(fn -> shown_text(a, second) == "<p>B's work, B gone</p>" end)
    kill_live(b)

    Brando.endpoint().subscribe("user:#{c.me.id}")
    {:ok, proposal} = Proposals.propose([%DeleteBlock{target: {Page, c.identity.id}, block_uid: second}], c.user)
    {:ok, _} = Proposals.approve(proposal.id, proposal.version, c.user)
    {:ok, _} = Proposals.apply(proposal.id, proposal.version, c.user)

    kept = second <> "-kept"
    await(fn -> session_state(c.identity).statuses[kept] == :inserted end)
    await(fn -> shown_text(a, kept) == "<p>B's work, B gone</p>" end)
    assert_receive %Phoenix.Socket.Broadcast{event: "toast"}, 2_000
  end

  # Two editors in one block that another write removes: one of them brings
  # it back, not both.
  test "a removed block two editors worked in comes back once", c do
    [_first, second | _] = c.uids
    a = open(c.conn, c.identity)
    b = open(c.other_conn, c.identity)
    type(a, second, "<p>A</p>")
    await(fn -> shown_text(b, second) == "<p>A</p>" end)
    type(b, second, "<p>A and B</p>")
    await(fn -> shown_text(a, second) == "<p>A and B</p>" end)

    {:ok, proposal} = Proposals.propose([%DeleteBlock{target: {Page, c.identity.id}, block_uid: second}], c.user)
    {:ok, _} = Proposals.approve(proposal.id, proposal.version, c.user)
    {:ok, _} = Proposals.apply(proposal.id, proposal.version, c.user)

    await(fn -> session_state(c.identity).statuses[second <> "-kept"] == :inserted end)
    Process.sleep(300)
    assert length(session_state(c.identity).order) == 3
  end

  # Follow-up: a child with unsaved work, removed by another write, came
  # back as a root block of its own: a multi module's entry outside its
  # module. It now goes back where it was.
  describe "a removed child with unsaved work" do
    setup c do
      c = Brando.ProposalFixtures.multi_context(c)
      [alpha | _] = c.child_uids
      b = open(c.other_conn, c.work)
      set_child(b, alpha, ["child_block", "refs", "0", "data", "data", "text"], "<p>Alpha, by B</p>")
      await(fn -> inspect(session_state(c.work).diffs[alpha]) =~ "Alpha, by B" end)
      Map.merge(c, %{alpha: alpha, b: b})
    end

    defp delete_outside(c, uid) do
      {:ok, proposal} = Proposals.propose([%DeleteBlock{target: {Page, c.work.id}, block_uid: uid}], c.user)
      {:ok, _} = Proposals.approve(proposal.id, proposal.version, c.user)
      {:ok, _} = Proposals.apply(proposal.id, proposal.version, c.user)
    end

    defp kept_text(state, uid),
      do: get_in(state.diffs, [uid, "refs"]) |> Enum.find(&(&1["name"] == "info")) |> get_in(["data", "data", "text"])

    test "comes back under its parent, when the parent is still there", c do
      delete_outside(c, c.alpha)
      kept = c.alpha <> "-kept"
      await(fn -> session_state(c.work).statuses[kept] == :inserted end)

      state = session_state(c.work)
      assert state.parents[kept] == c.multi_uid
      assert state.child_order[c.multi_uid] == tl(c.child_uids) ++ [kept]
      refute kept in state.order
      assert kept_text(state, kept) == "<p>Alpha, by B</p>"

      stay(c.b)
      save_read(c.b)
      save_write(c.b)

      # a container with its children: give a loaded test run time
      await(
        fn ->
          c.work |> rows() |> Enum.find(&(&1.block.uid == c.multi_uid)) |> then(&(length(&1.block.children) == 3))
        end,
        500
      )
    end

    test "comes back inside its removed parent, kept around it alone, when the parent went too", c do
      delete_outside(c, c.multi_uid)
      kept = c.alpha <> "-kept"
      shell = c.multi_uid <> "-kept"
      await(fn -> session_state(c.work).statuses[kept] == :inserted end)

      state = session_state(c.work)
      assert state.order == [c.intro_uid, shell]
      assert state.child_order[shell] == [kept]
      assert kept_text(state, kept) == "<p>Alpha, by B</p>"
    end
  end

  # Round 3 #2: an Assistant proposal applied between a save collecting its
  # blocks and writing them. The rebase gave the form the new rows, the
  # save's blocks lacked the new one, and the write deleted it.
  test "an outside write between a save's collect and its write keeps its new block", c do
    [first | _] = c.uids
    a = open(c.conn, c.identity)
    stay(a)
    type(a, first, "<p>A's edit</p>")
    save_read(a)

    op = %InsertBlock{
      target: {Page, c.identity.id},
      module: c.case_module.id,
      placement: {:after, first},
      values: %{heading: "From the assistant"}
    }

    {:ok, proposal} = Proposals.propose([op], c.user)
    {:ok, _} = Proposals.approve(proposal.id, proposal.version, c.user)
    {:ok, _} = Proposals.apply(proposal.id, proposal.version, c.user)
    inserted = c.identity |> rows() |> Enum.at(1)
    await(fn -> render(a) =~ ~s(data-block-uid="#{inserted.block.uid}") end)

    # the write the first submit asked for collects the blocks again first
    save_read(a)
    save_write(a)

    await(fn ->
      row = c.identity |> rows() |> Enum.find(&(&1.block.uid == first))
      hd(row.block.refs).data.data.text == "<p>A's edit</p>"
    end)

    assert Enum.any?(rows(c.identity), &(&1.block.uid == inserted.block.uid))
    assert length(rows(c.identity)) == 4
  end

  # Round 3 #4: undoing a proposal restored a revision inside a transaction
  # and synced the open editors at once, from rows that were not committed
  # and, rolled back, never existed.
  test "an outside write reaches open editors only once its transaction commits", c do
    _b = open(c.other_conn, c.identity)
    ref = EditSession.ref(Page, c.identity.id, c.identity.language)
    Phoenix.PubSub.subscribe(Brando.pubsub(), ref.topic)
    page = Repo.get!(Page, c.identity.id)

    {:error, :rolled_back} =
      Brando.Repo.transaction(fn ->
        EditSession.sync_saved(page)
        Brando.Repo.rollback(:rolled_back)
      end)

    refute_receive {:edit_session, _, %{kind: :rebase}}, 300

    {:ok, :committed} =
      Brando.Repo.transaction(fn ->
        EditSession.sync_saved(page)
        refute_receive {:edit_session, _, %{kind: :rebase}}, 100
        :committed
      end)

    assert_receive {:edit_session, _, %{kind: :rebase}}, 2_000
  end

  # Round 3 #1 (field ops): A backspaced in one field while B typed in
  # another field of the same block, and A's edit was taken for an echo of
  # the form before B's change, and dropped.
  test "a backspace right after another editor typed elsewhere in the block is kept", c do
    [first | _] = c.uids
    desc = ["entry_block", "block", "description"]
    a = open(c.conn, c.identity)
    b = open(c.other_conn, c.identity)

    set = fn view, path, value ->
      selector = "#entry_block_form-#{first}"
      params = view |> render() |> form_params(selector) |> put_in(path, value) |> Map.put("_target", path)
      view |> element(selector) |> render_change(params)
    end

    shown = fn view, path -> view |> render() |> form_params("#entry_block_form-#{first}") |> get_in(path) end

    set.(a, desc, "abc")
    await(fn -> shown.(b, desc) == "abc" end)
    set.(b, text_path(), "<p>B typing</p>")
    await(fn -> shown.(a, text_path()) == "<p>B typing</p>" end)
    set.(a, desc, "abcd")
    set.(a, desc, "abc")

    await(fn -> get_in(session_state(c.identity).diffs, [first, "block", "description"]) == "abc" end)
    await(fn -> shown.(b, desc) == "abc" end)
    assert shown.(a, text_path()) == "<p>B typing</p>"
  end

  # Round 4: A set the field B had just changed back to A's old value, and it
  # was taken for an echo of the form before B's change.
  test "setting a field back right after another editor changed it is kept", c do
    [first | _] = c.uids
    desc = ["entry_block", "block", "description"]
    a = open(c.conn, c.identity)
    b = open(c.other_conn, c.identity)

    set = fn view, value ->
      selector = "#entry_block_form-#{first}"
      params = view |> render() |> form_params(selector) |> put_in(desc, value) |> Map.put("_target", desc)
      view |> element(selector) |> render_change(params)
    end

    shown = fn view -> view |> render() |> form_params("#entry_block_form-#{first}") |> get_in(desc) end

    set.(a, "abc")
    await(fn -> shown.(b) == "abc" end)
    set.(b, "abcB")
    # A's form shows B's change: setting it back is a change, not a no-op
    await(fn -> shown.(a) == "abcB" end)
    set.(a, "abc")

    await(fn -> get_in(session_state(c.identity).diffs, [first, "block", "description"]) == "abc" end)
    await(fn -> shown.(b) == "abc" end)
  end

  # Follow-up, round 2: a toggle set back, or a backspace to the text from
  # before, within a second of another editor's change to the same field.
  for {name, path, theirs, mine} <- [
        {"a toggle set back", ["entry_block", "block", "active"], "false", "true"},
        {"a backspace to the text before", ["entry_block", "block", "refs", "0", "data", "data", "text"], "<p>B's</p>",
         "<p>Identity 0</p>"}
      ] do
    test "#{name} right after another editor changed the field is kept", c do
      [first | _] = c.uids
      path = unquote(path)
      a = open(c.conn, c.identity)
      b = open(c.other_conn, c.identity)
      selector = "#entry_block_form-#{first}"

      set = fn view, value ->
        params = view |> render() |> form_params(selector) |> put_in(path, value) |> Map.put("_target", path)
        view |> element(selector) |> render_change(params)
      end

      shown = fn view -> view |> render() |> form_params(selector) |> get_in(path) end
      before = shown.(a)

      set.(b, unquote(theirs))
      await(fn -> shown.(a) == unquote(theirs) end)
      set.(a, unquote(mine))
      assert unquote(mine) == before

      await(fn -> shown.(b) == unquote(mine) end)
    end
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

  # The revisions drawer's preview loads a revision as an unsaved working
  # copy, replacing the editor's unsaved changes. Those stayed in the edit
  # session as unsaved work: a replica rejoined with them when the session
  # stopped, or the session, still running for others, carried them back
  # over the revision when it was activated or saved.
  describe "a revision loaded as a working copy" do
    setup c do
      previous = Application.get_env(:brando, EditSession, [])
      on_exit(fn -> Application.put_env(:brando, EditSession, previous) end)

      [first, second | _] = c.uids
      Map.merge(c, %{first: first, second: second})
    end

    defp revisions(page),
      do: Repo.one(from(r in Brando.Revisions.Revision, where: r.entry_id == ^page.id, select: max(r.revision)))

    # Revision: the working copy, stored from the editor's unsaved state.
    # Then an edit the preview discards, and the preview.
    defp load_working_copy(a, c) do
      drawer = cid_of(a, "#page_form-revisions-drawer-tab-activity")
      type(a, c.first, "<p>Working-copy block</p>")
      a |> with_target(form_cid(a)) |> render_hook("store_revision", %{})
      await(fn -> revisions(c.identity) != nil end)
      revision = revisions(c.identity)

      type(a, c.first, "<p>Discard this block</p>")
      a |> with_target(drawer) |> render_hook("select_revision", %{"revision" => revision})
      await(fn -> shown_text(a, c.first) == "<p>Working-copy block</p>" end)
      {drawer, revision}
    end

    # the block fields mount again from the written entry
    defp await_remount(a, c) do
      await(fn -> shown_text(a, c.first) != nil end)
      Process.sleep(300)
    end

    for grace <- [0, 30_000] do
      test "activating it keeps the working copy, not the edits it replaced (grace #{grace} ms)", c do
        Application.put_env(:brando, EditSession, grace_period: unquote(grace))
        a = open(c.conn, c.identity)
        {drawer, revision} = load_working_copy(a, c)

        a |> with_target(drawer) |> render_hook("activate_revision", %{"value" => revision})
        await(fn -> Map.new(texts(c.identity))[c.first] == "<p>Working-copy block</p>" end)
        await_remount(a, c)

        assert shown_text(a, c.first) == "<p>Working-copy block</p>"
        refute inspect(session_state(c.identity).diffs) =~ "Discard this block"
      end
    end

    # Page obfuscates `uri` in the trash; a revision from before has the real one.
    test "of an entry in the trash, it keeps the address the trash gave it", c do
      {:ok, revision} = Brando.Revisions.create_revision(Repo.get!(Page, c.identity.id), c.me, false)
      {:ok, trashed} = Brando.Repo.soft_delete(Repo.get!(Page, c.identity.id))
      assert trashed.uri =~ "$$$"

      a = open(c.conn, trashed)
      drawer = cid_of(a, "#page_form-revisions-drawer-tab-activity")
      a |> with_target(drawer) |> render_hook("select_revision", %{"revision" => revision.revision})
      await(fn -> render(a) =~ ~r/draft-save-state" data-state="dirty"/ end)

      [uri] = a |> render() |> Floki.parse_document!() |> Floki.attribute(~s(#page_form_form [name$="[uri]"]), "value")
      assert uri == trashed.uri
    end

    test "saving it writes the working copy, and another editor's later work stays", c do
      Application.put_env(:brando, EditSession, grace_period: 30_000)
      a = open(c.conn, c.identity)
      b = open(c.other_conn, c.identity)
      load_working_copy(a, c)
      assert render(a) =~ ~r/draft-save-state" data-state="dirty"/

      type(b, c.second, "<p>B, after the preview</p>")
      await(fn -> inspect(session_state(c.identity).diffs) =~ "B, after the preview" end)

      stay(a)
      save_read(a)
      save_write(a)
      await(fn -> Map.new(texts(c.identity))[c.first] == "<p>Working-copy block</p>" end)
      await_remount(a, c)

      await(fn -> shown_text(b, c.first) == "<p>Working-copy block</p>" end)
      assert shown_text(b, c.second) == "<p>B, after the preview</p>"
      assert shown_text(a, c.first) == "<p>Working-copy block</p>"
      refute inspect(session_state(c.identity).diffs) =~ "Discard this block"
    end

    test "another editor's work after the preview loaded is kept when it is activated", c do
      Application.put_env(:brando, EditSession, grace_period: 30_000)
      a = open(c.conn, c.identity)
      b = open(c.other_conn, c.identity)
      {drawer, revision} = load_working_copy(a, c)

      type(b, c.second, "<p>B, after the preview</p>")
      await(fn -> inspect(session_state(c.identity).diffs) =~ "B, after the preview" end)

      a |> with_target(drawer) |> render_hook("activate_revision", %{"value" => revision})
      await(fn -> Map.new(texts(c.identity))[c.first] == "<p>Working-copy block</p>" end)
      await_remount(a, c)

      await(fn -> shown_text(b, c.first) == "<p>Working-copy block</p>" end)
      assert shown_text(b, c.second) == "<p>B, after the preview</p>"
      assert shown_text(a, c.first) == "<p>Working-copy block</p>"
      assert shown_text(a, c.second) == "<p>B, after the preview</p>"
    end
  end

  # Loading a revision as a working copy made the revision's rows the form's
  # data, so the form held no changes and Save wrote nothing: the editor
  # showed the revision restored while the database kept what it had.
  describe "saving a revision loaded as a working copy" do
    defp work_rows(page) do
      Page
      |> Repo.get!(page.id)
      |> Repo.preload([entry_blocks: [block: [:refs, :vars, children: [:refs, :vars]]]], force: true)
      |> Map.get(:entry_blocks)
      |> Enum.sort_by(& &1.sequence)
    end

    defp content(page) do
      page = Repo.get!(Page, page.id)

      blocks =
        Enum.map(work_rows(page), fn %{block: block} ->
          %{
            module_id: block.module_id,
            refs: block.refs |> Enum.map(&{&1.name, get_in(&1.data.data, [Access.key(:text)])}) |> Enum.sort(),
            children:
              Enum.map(block.children, fn child ->
                {child.refs |> Enum.map(&{&1.name, get_in(&1.data.data, [Access.key(:text)])}) |> Enum.sort(),
                 Enum.map(child.vars, &{&1.key, &1.value})}
              end)
          }
        end)

      vars = Brando.Content.Var |> where([v], v.page_id == ^page.id) |> Repo.all() |> Enum.map(&{&1.key, &1.value})
      {page.title, vars, blocks}
    end

    defp set_child(view, uid, path, value) do
      selector = "#child_block_form-#{uid}"
      params = view |> render() |> form_params(selector) |> put_in(path, value) |> Map.put("_target", path)
      view |> element(selector) |> render_change(params)
    end

    test "writes the revision's fields, blocks and nested refs and vars", c do
      c = Brando.ProposalFixtures.multi_context(c)
      [alpha | _] = c.child_uids

      var =
        Repo.insert!(%Brando.Content.Var{
          type: :string,
          key: "subtitle",
          label: "Subtitle",
          value: "As in the revision",
          page_id: c.work.id,
          sequence: 0
        })

      entry = Page |> Repo.get!(c.work.id) |> Repo.preload(Brando.Blueprint.preloads_for(Page))
      {:ok, _} = Brando.Revisions.create_revision(entry, c.user)
      revision = revisions(c.work)
      before = content(c.work)

      # the entry moves on: fields (one an entry var), a nested ref and var,
      # a block removed and one added
      var |> Ecto.Changeset.change(value: "Moved on") |> Repo.update!()
      a = open(c.conn, c.work)
      stay(a)

      a
      |> form("#page_form_form")
      |> render_change(%{"page" => %{"title" => "Moved on"}, "_target" => ["page", "title"]})

      set_child(a, alpha, ["child_block", "refs", "0", "data", "data", "text"], "<p>Alpha, moved on</p>")
      set_child(a, alpha, ["child_block", "vars", "0", "value"], "50")
      Phoenix.LiveView.send_update(a.pid, BlockField, id: @block_field, event: "delete_block", uid: c.intro_uid)
      insert_block(a, c, 1)
      await(fn -> length(session_state(c.work).order) == 2 and c.intro_uid not in session_state(c.work).order end)
      save_read(a)
      save_write(a)
      await(fn -> content(c.work) != before and elem(content(c.work), 0) == "Moved on" end)
      moved_on = content(c.work)
      assert moved_on != before

      # the revision, loaded and saved
      drawer = cid_of(a, "#page_form-revisions-drawer-tab-activity")
      a |> with_target(drawer) |> render_hook("select_revision", %{"revision" => revision})
      title = fn -> a |> render() |> form_params("#page_form_form") |> get_in(["page", "title"]) end
      await(fn -> title.() == "Work" end)
      # the editor says it has unsaved changes
      assert render(a) =~ ~r/draft-save-state" data-state="dirty"/

      stay(a)
      save_read(a)
      save_write(a)

      await(fn -> content(c.work) == before end)
      assert Process.alive?(a.pid)
    end
  end
end

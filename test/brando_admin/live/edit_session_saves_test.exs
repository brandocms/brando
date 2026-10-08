defmodule BrandoAdmin.EditSessionSavesTest do
  # Saves, outside writes and recovery copies with two editors in one entry's
  # edit session, through real LiveViews. Each test is a case a review found
  # losing or corrupting work (#2992).
  use Brando.LiveCase

  import Brando.EditSessionEditors
  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Proposals
  alias Brando.Content.Proposals.DeleteBlock
  alias Brando.Content.Proposals.InsertBlock
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

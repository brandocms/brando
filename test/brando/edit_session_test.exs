defmodule Brando.EditSessionTest do
  use ExUnit.Case, async: false

  import Brando.Test.Support, only: [put_test_env: 2]

  alias Brando.EditSession
  alias Brando.EditSession.Data
  alias Brando.Tenant
  alias BrandoAdmin.Components.Form.BlockField.Ops
  alias BrandoAdmin.Components.Form.BlockField.Replica

  @field :blocks

  defp entry_block(uid, entry_block_id, block_id, children \\ []),
    do: %{id: entry_block_id, block: %{uid: uid, id: block_id, children: children}}

  defp child(uid, block_id), do: %{uid: uid, id: block_id, children: []}

  defp rows, do: Ops.from_entry_blocks([entry_block("a", 1, 10, [child("a1", 11)]), entry_block("b", 2, 20)])

  defp new_ref, do: EditSession.ref(Brando.Pages.Page, System.unique_integer([:positive]))

  # An editor in its own process: joins, applies its own ops optimistically
  # (`Replica`), casts them, and applies whatever the session broadcasts.
  defp editor(ref, base \\ rows(), opts \\ []) do
    test = self()

    pid =
      spawn_link(fn ->
        Phoenix.PubSub.subscribe(Brando.pubsub(), ref.topic)
        {:ok, info} = EditSession.join(ref, @field, {base, Keyword.get(opts, :held, base)}, opts)
        send(test, {:joined, self(), info})
        editor_loop(%Replica{} = Replica.new(ref, info, nil), test)
      end)

    assert_receive {:joined, ^pid, info}
    {pid, info}
  end

  defp editor_loop(replica, test) do
    receive do
      {:local, op} ->
        {replica, seq} = Replica.local(replica, op)
        EditSession.submit(replica.session, @field, op, seq)
        editor_loop(replica, test)

      {:edit_session, @field, %{kind: :op} = message} ->
        replica =
          case Replica.receive_op(replica, message) do
            {:own, replica} -> replica
            {:remote, replica, _displayed} -> replica
            :stale -> replica
          end

        editor_loop(replica, test)

      {:edit_session, @field, %{kind: :rebase} = message} ->
        {replica, _} = if Replica.newer?(replica, message), do: Replica.reset(replica, message), else: {replica, nil}
        editor_loop(replica, test)

      {:edit_session, @field, %{kind: :rejected} = message} ->
        {replica, _, _op} = Replica.receive_rejected(replica, message)
        editor_loop(replica, test)

      {:state, from} ->
        send(from, {:state, self(), replica})
        editor_loop(replica, test)
    end
  end

  defp replica_of(pid) do
    send(pid, {:state, self()})
    assert_receive {:state, ^pid, replica}
    replica
  end

  defp session_state(ref) do
    {:ok, %{state: state, rev: rev}} = EditSession.fetch(EditSession.whereis(ref), @field)
    {state, rev}
  end

  # Waits until the editor has cast all it holds and applied everything the
  # session has.
  defp settled(pid, ref) do
    Enum.reduce_while(1..200, nil, fn _, _ ->
      replica = replica_of(pid)
      {state, rev} = session_state(ref)

      if replica.rev == rev and replica.pending == [] do
        {:halt, {Replica.displayed(replica), state}}
      else
        Process.sleep(5)
        {:cont, nil}
      end
    end) || flunk("editor never caught up with the session")
  end

  describe "ordering" do
    test "ops get consecutive revisions and are broadcast in the order they arrive" do
      ref = new_ref()
      Phoenix.PubSub.subscribe(Brando.pubsub(), ref.topic)
      {:ok, info} = EditSession.join(ref, @field, {rows(), rows()})
      assert info.rev == 0
      assert info.seeded?

      EditSession.submit(info.session, @field, {:update, "a", %{"block" => %{"anchor" => "one"}}}, 1)
      EditSession.submit(info.session, @field, {:insert, "n", 1, %{"block" => %{"uid" => "n"}}}, 2)
      EditSession.submit(info.session, @field, {:move, "b", 0}, 3)

      me = self()

      for {rev, seq} <- [{1, 1}, {2, 2}, {3, 3}] do
        assert_receive {:edit_session, @field, %{kind: :op, rev: ^rev, origin: {^me, ^seq}}}
      end

      {state, 3} = session_state(ref)
      assert state.order == ["b", "a", "n"]
      assert state.diffs["a"] == %{"block" => %{"anchor" => "one"}}
    end

    @tag :capture_log
    test "a rejected op goes back to its sender alone and moves no revision" do
      ref = new_ref()
      {:ok, info} = EditSession.join(ref, @field, {rows(), rows()})
      epoch = info.epoch

      EditSession.submit(info.session, @field, {:delete, "ghost"}, 7)
      assert_receive {:edit_session, @field, %{kind: :rejected, seq: 7, epoch: ^epoch, reason: {:unknown_uid, "ghost"}}}
      assert {_state, 0} = session_state(ref)
    end

    @tag :capture_log
    test "an op that raises is rejected and the session lives on" do
      ref = new_ref()
      {:ok, info} = EditSession.join(ref, @field, {rows(), rows()})

      # params must be a map; a list reaches the reducer's map functions
      EditSession.submit(info.session, @field, {:update, "a", %{"block" => [:not, :params]}}, 1)
      assert_receive {:edit_session, @field, %{kind: :rejected, seq: 1}}
      assert Process.alive?(info.session)
    end
  end

  describe "two editors" do
    test "concurrent inserts at the same place converge on the session's order" do
      ref = new_ref()
      {a, _} = editor(ref)
      {b, _} = editor(ref)

      # Both put a block at index 1 before seeing the other's.
      send(a, {:local, {:insert, "from_a", 1, %{"block" => %{"uid" => "from_a"}}}})
      send(b, {:local, {:insert, "from_b", 1, %{"block" => %{"uid" => "from_b"}}}})
      send(a, {:local, {:update, "b", %{"block" => %{"anchor" => "a"}}}})
      send(b, {:local, {:update, "a1", %{"description" => "b"}}})

      {shown_a, state} = settled(a, ref)
      {shown_b, ^state} = settled(b, ref)

      assert shown_a == state
      assert shown_b == state
      assert Enum.sort(state.order) == ["a", "b", "from_a", "from_b"]
      assert state.diffs["b"] == %{"block" => %{"anchor" => "a"}}
      assert state.diffs["a1"] == %{"description" => "b"}
    end

    test "a pending op is replayed on top of another editor's op" do
      replica = Replica.new(%{}, %{session: self(), epoch: 1, rev: 0, state: rows()}, nil)

      # Our insert at 0 is still in flight when the other editor's arrives.
      {replica, 1} = Replica.local(replica, {:insert, "mine", 0, %{}})

      {:remote, replica, shown} =
        Replica.receive_op(replica, %{epoch: 1, rev: 1, op: {:insert, "theirs", 0, %{}}, origin: {:other, 1}})

      assert shown.order == ["mine", "theirs", "a", "b"]

      # The session applied it second, so that is where it ends up.
      {:own, replica} =
        Replica.receive_op(replica, %{epoch: 1, rev: 2, op: {:insert, "mine", 0, %{}}, origin: {self(), 1}})

      assert Replica.displayed(replica).order == ["mine", "theirs", "a", "b"]
      assert replica.pending == []
    end

    test "a field this editor set keeps its value until the session confirms it" do
      path = ["block", "anchor"]
      replica = Replica.new(%{}, %{session: self(), epoch: 1, rev: 0, state: rows()}, nil)
      shown = fn replica -> get_in(Replica.displayed(replica).diffs, ["b" | path]) end

      # Our keystroke is in flight when another editor's value for the same
      # field arrives first: we keep showing ours, no flicker back.
      {replica, 1} = Replica.local(replica, {:set_field, "b", path, "mine", 0})
      remote = {:set_field, "b", path, "theirs", 0}
      {:remote, replica, displayed} = Replica.receive_op(replica, %{epoch: 1, rev: 1, op: remote, origin: {:other, 1}})
      assert get_in(displayed.diffs, ["b" | path]) == "mine"

      # The session applied ours after theirs: ours is the last to arrive.
      {:own, replica} =
        Replica.receive_op(replica, %{epoch: 1, rev: 2, op: {:set_field, "b", path, "mine", 0}, origin: {self(), 1}})

      assert shown.(replica) == "mine"

      # A later value from the other editor wins.
      {:remote, replica, _} =
        Replica.receive_op(replica, %{epoch: 1, rev: 3, op: {:set_field, "b", path, "later", 2}, origin: {:other, 2}})

      assert shown.(replica) == "later"
    end

    test "two editors in different fields of one block both keep theirs, in the session" do
      ref = new_ref()
      {a, _} = editor(ref)
      {b, _} = editor(ref)

      send(a, {:local, {:set_field, "b", ["block", "anchor"], "by A", 0}})
      send(b, {:local, {:set_field, "b", ["block", "description"], "by B", 0}})
      send(a, {:local, {:set_field, "b", ["block", "description"], "A, later", 0}})

      {shown_a, state} = settled(a, ref)
      {shown_b, ^state} = settled(b, ref)
      assert shown_a == state and shown_b == state
      assert state.diffs["b"]["block"]["anchor"] == "by A"
      assert state.diffs["b"]["block"]["description"] in ["by B", "A, later"]
    end

    test "a gap in revisions asks for the session's state" do
      replica = Replica.new(%{}, %{session: self(), epoch: 1, rev: 0, state: rows()}, nil)
      assert Replica.receive_op(replica, %{epoch: 1, rev: 2, op: {:move, "a", 1}, origin: nil}) == :resync
      assert Replica.receive_op(replica, %{epoch: 1, rev: 0, op: {:move, "a", 1}, origin: nil}) == :stale
      assert Replica.receive_op(replica, %{epoch: 2, rev: 1, op: {:move, "a", 1}, origin: nil}) == :stale
    end
  end

  describe "joining" do
    test "a late joiner gets the session's unsaved state" do
      ref = new_ref()
      {a, _} = editor(ref)
      send(a, {:local, {:update, "b", %{"block" => %{"anchor" => "unsaved"}}}})
      send(a, {:local, {:insert, "n", :end, %{"block" => %{"uid" => "n"}}}})
      {_shown, state} = settled(a, ref)

      {:ok, info} = EditSession.join(ref, @field, {rows(), rows()})
      refute info.seeded?
      assert info.state == state
      assert info.state.diffs["b"] == %{"block" => %{"anchor" => "unsaved"}}
      assert info.rev == 2
    end

    test "a joiner with other rows is told, and can carry the session onto them" do
      ref = new_ref()
      {a, _} = editor(ref)
      send(a, {:local, {:update, "b", %{"block" => %{"anchor" => "unsaved"}}}})
      settled(a, ref)

      newer =
        Ops.from_entry_blocks([
          entry_block("a", 1, 10, [child("a1", 11)]),
          entry_block("b", 2, 20),
          entry_block("c", 3, 30)
        ])

      assert EditSession.join(ref, @field, {newer, newer}) == {:error, :base_mismatch}

      Phoenix.PubSub.subscribe(Brando.pubsub(), ref.topic)
      assert {:ok, info} = EditSession.join(ref, @field, {newer, newer}, rebase: true)
      assert info.state.order == ["a", "b", "c"]
      assert info.state.diffs["b"] == %{"block" => %{"anchor" => "unsaved"}}
      assert_receive {:edit_session, @field, %{kind: :rebase, reason: :joined}}

      {shown, state} = settled(a, ref)
      assert shown == state
    end
  end

  describe "saves" do
    test "the rebase after a save replays only what arrived while it ran" do
      ref = new_ref()
      {other, _} = editor(ref)
      {:ok, info} = EditSession.join(ref, @field, {rows(), rows()})
      saver = info.session

      EditSession.submit(saver, @field, {:insert, "saved", :end, %{"block" => %{"uid" => "saved"}}}, 1)
      {:ok, %{rev: save_rev, state: read}} = EditSession.fetch(saver, @field, purpose: :save)
      assert "saved" in read.order

      # While the save runs, the other editor keeps typing.
      send(other, {:local, {:update, "a1", %{"description" => "during the save"}}})
      settled(other, ref)

      saved_rows =
        Ops.from_entry_blocks([
          entry_block("a", 1, 10, [child("a1", 11)]),
          entry_block("b", 2, 20),
          entry_block("saved", 9, 90)
        ])

      assert {:ok, after_save} = EditSession.rebase(saver, @field, saved_rows, {:after, save_rev})
      state = after_save.state

      # "saved" is a row now; the op from during the save is still unsaved.
      assert state.statuses["saved"] == :persisted
      assert state.db_ids["saved"] == {9, 90}
      assert state.diffs["a1"] == %{"description" => "during the save"}
      refute Map.has_key?(state.diffs, "saved")

      {shown, ^state} = settled(other, ref)
      assert shown == state
    end

    test "without a save in flight the session keeps no log" do
      data = Data.new(1)
      {:seeded, data} = Data.join(data, @field, rows(), rows())
      {:ok, data} = Data.apply_op(data, @field, {:update, "b", %{"block" => %{"anchor" => "x"}}})
      assert data.fields[@field].log == []

      data = Data.mark_save(data, @field, :client, 0)
      {:ok, data} = Data.apply_op(data, @field, {:update, "b", %{"block" => %{"anchor" => "y"}}})
      assert [{2, _op}] = data.fields[@field].log

      {:ok, data, []} = Data.rebase(data, @field, rows(), {:after, 1, :client})
      assert data.fields[@field].log == []
      assert data.fields[@field].marks == %{}
    end
  end

  describe "lifecycle" do
    test "the session stops a grace period after its last editor leaves" do
      put_test_env(EditSession, grace_period: 80)
      ref = new_ref()
      {a, info} = editor(ref)
      session = info.session
      monitor = Process.monitor(session)

      unlink_and_kill(a)
      refute_receive {:DOWN, ^monitor, _, _, _}, 40

      # Someone comes back within the grace period: the session stays.
      {b, _} = editor(ref)
      refute_receive {:DOWN, ^monitor, _, _, _}, 150
      assert EditSession.whereis(ref) == session

      unlink_and_kill(b)
      assert_receive {:DOWN, ^monitor, :process, ^session, :normal}, 500
      wait_until(fn -> EditSession.whereis(ref) == nil end)
    end

    test "a crashed session is re-seeded by its replicas and loses nothing" do
      ref = new_ref()
      {a, _} = editor(ref)
      {b, _} = editor(ref)
      send(a, {:local, {:update, "a", %{"block" => %{"anchor" => "before the crash"}}}})
      {held, _} = settled(a, ref)
      settled(b, ref)

      session = EditSession.whereis(ref)
      Process.exit(session, :kill)
      wait_until(fn -> EditSession.whereis(ref) != session end)

      # A comes back first and seeds the new session with what it shows; B,
      # which had an op of its own in flight, joins that and casts it again.
      {:ok, a_info} = EditSession.join(ref, @field, {rows(), held})
      assert a_info.seeded?
      assert a_info.state.diffs["a"] == %{"block" => %{"anchor" => "before the crash"}}

      b_replica = replica_of(b)
      {:ok, b_info} = EditSession.join(ref, @field, {rows(), Replica.displayed(b_replica)})
      refute b_info.seeded?
      EditSession.submit(b_info.session, @field, {:update, "b", %{"block" => %{"anchor" => "recast"}}}, 1)

      wait_until(fn -> match?({%{diffs: %{"b" => _}}, _}, session_state(ref)) end)
      {state, _} = session_state(ref)
      assert state.diffs["a"] == %{"block" => %{"anchor" => "before the crash"}}
      assert state.diffs["b"] == %{"block" => %{"anchor" => "recast"}}
    end
  end

  describe "found in review" do
    defp anchor(uid, value), do: {:update, uid, %{"block" => %{"anchor" => value}}}

    # R1: the session applied A's op and then a save's rebase; A takes the
    # rebase reply before its own op's broadcast. Replaying the op over the
    # rebased state put A's old value back over a later one.
    test "a reset drops the pending ops the session's state already holds" do
      base = rows()
      {:ok, with_a} = Ops.apply_op(base, anchor("b", "A typed"))
      replica = Replica.new(nil, %{session: nil, epoch: 1, rev: 0, state: base}, nil)
      {replica, 1} = Replica.local(replica, anchor("b", "A typed"))

      {replica, _} = Replica.reset(replica, %{epoch: 1, rev: 2, state: with_a, seq: 1})
      assert replica.pending == []
      assert :stale == Replica.receive_op(replica, %{epoch: 1, rev: 1, op: anchor("b", "A typed"), origin: {self(), 1}})

      {:remote, _replica, shown} =
        Replica.receive_op(replica, %{epoch: 1, rev: 3, op: anchor("b", "B typed later"), origin: {:other, 1}})

      assert shown.diffs["b"]["block"]["anchor"] == "B typed later"

      # A broadcast rebase names the handled op by this process
      replica = Replica.new(nil, %{session: nil, epoch: 1, rev: 0, state: base}, nil)
      {replica, 1} = Replica.local(replica, anchor("b", "A typed"))
      {replica, 2} = Replica.local(replica, anchor("a", "not yet"))
      {replica, _} = Replica.reset(replica, %{epoch: 1, rev: 2, state: with_a, seqs: %{self() => 1}})
      assert [{2, _}] = replica.pending
    end

    test "the session tells a replica which of its ops it has handled" do
      ref = new_ref()
      {:ok, info} = EditSession.join(ref, @field, {rows(), rows()})
      EditSession.submit(info.session, @field, anchor("b", "one"), 1)
      EditSession.submit(info.session, @field, {:delete, "ghost"}, 2)
      assert {:ok, %{seq: 2}} = EditSession.fetch(info.session, @field)
    end

    # R2: after a crash, a fresh editor reached the new session first and
    # seeded it from the database; A's confirmed but unsaved work was lost.
    test "a replica coming back after a crash carries its work onto a session a fresh joiner seeded" do
      ref = new_ref()
      Phoenix.PubSub.subscribe(Brando.pubsub(), ref.topic)
      base = rows()
      {:ok, info} = EditSession.join(ref, @field, {base, base})
      EditSession.submit(info.session, @field, anchor("b", "unsaved by A"), 1)
      assert_receive {:edit_session, @field, %{kind: :op, rev: 1}}
      {:ok, held} = Ops.apply_op(base, anchor("b", "unsaved by A"))

      monitor = Process.monitor(info.session)
      Process.exit(info.session, :kill)
      assert_receive {:DOWN, ^monitor, _, _, _}
      wait_until(fn -> EditSession.whereis(ref) == nil end)

      fresh = Task.async(fn -> EditSession.join(ref, @field, {base, base}) end)
      assert {:ok, %{seeded?: true}} = Task.await(fresh)

      assert {:ok, back} = EditSession.join(ref, @field, {base, held})
      refute back.seeded?
      assert back.state.diffs["b"]["block"]["anchor"] == "unsaved by A"
      # and the others hear about it
      assert_receive {:edit_session, @field, %{kind: :rebase, reason: :joined, state: state}}
      assert state.diffs["b"]["block"]["anchor"] == "unsaved by A"
    end

    test "a replica whose rows changed under it carries its work onto the newer rows" do
      ref = new_ref()
      base = rows()
      {:ok, _} = EditSession.join(ref, @field, {base, base})

      newer =
        Ops.from_entry_blocks([
          entry_block("a", 1, 10, [child("a1", 11)]),
          entry_block("b", 2, 20),
          entry_block("c", 3, 30)
        ])

      {:ok, held} = Ops.apply_op(base, anchor("a", "held"))

      assert {:ok, info} = EditSession.join(ref, @field, {newer, held}, rebase: true, held_base: base)
      assert info.state.order == ["a", "b", "c"]
      assert info.state.diffs["a"]["block"]["anchor"] == "held"
    end

    # R3: an unsaved move of a persisted child to another parent was dropped
    # without a word when someone else wrote the entry.
    test "carry keeps a child moved to another parent, and reports a move it cannot make" do
      old =
        Ops.from_entry_blocks([entry_block("a", 1, 10, [child("a1", 11)]), entry_block("b", 2, 20, [child("b1", 21)])])

      {:ok, moved} = Ops.apply_op(old, {:move_to_parent, "a1", "b", :end})

      assert {carried, []} = Ops.carry(moved, old, old)
      assert carried.child_order["b"] == ["b1", "a1"]
      assert carried.child_order["a"] == []

      # the new parent is gone in the new rows
      without_b = Ops.from_entry_blocks([entry_block("a", 1, 10, [child("a1", 11)])])
      assert {_carried, ["a1"]} = Ops.carry(moved, old, without_b)
    end

    test "a read-only editor follows the others but its ops are turned away" do
      ref = new_ref()
      {:ok, info} = EditSession.join(ref, @field, {rows(), rows()}, read_only: true)
      EditSession.submit(info.session, @field, anchor("b", "not allowed"), 1)
      assert_receive {:edit_session, @field, %{kind: :rejected, reason: :read_only}}
      assert {_state, 0} = session_state(ref)
    end

    # Round 3 #6: a rejoin carries what the editor holds onto the session's
    # state, and had no read-only check.
    # An editor that loads a revision as a working copy replaces its unsaved
    # changes. Writing that copy must not carry them back.
    test "rows an editor writes after detaching replace what the session held, keeping later ops" do
      ref = new_ref()
      {:ok, info} = EditSession.join(ref, @field, {rows(), rows()})
      EditSession.submit(info.session, @field, anchor("a", "replaced by the working copy"), 1)
      {other, _} = editor(ref)
      assert {%{diffs: %{"a" => _}}, 1} = session_state(ref)

      EditSession.detach(info.session, @field)
      send(other, {:local, anchor("b", "after the detach")})
      wait_until(fn -> elem(session_state(ref), 1) == 2 end)

      # the working copy is written: the rows are what this editor showed
      {:ok, _} = EditSession.rebase(info.session, @field, rows(), :carry)
      {state, _rev} = session_state(ref)
      refute Map.has_key?(state.diffs, "a")
      assert state.diffs["b"]["block"]["anchor"] == "after the detach"
    end

    test "a read-only editor brings none of what it holds into the session, joining or rejoining" do
      ref = new_ref()
      {:ok, held} = Ops.apply_op(rows(), anchor("b", "held by a read-only editor"))

      # seeding a new session
      {:ok, _} = EditSession.join(ref, @field, {rows(), held}, read_only: true)
      assert {state, 0} = session_state(ref)
      assert state.diffs == %{}

      # rejoining a known one
      {:ok, _} = EditSession.join(ref, @field, {rows(), held}, read_only: true)
      assert {state, 0} = session_state(ref)
      assert state.diffs == %{}
    end

    test "a save mark lives 30 seconds, and a save slower than that still rebases" do
      base = rows()
      {:seeded, data} = Data.join(Data.new(1), @field, base, base)
      {:ok, data} = Data.apply_op(data, @field, {:insert, "n", :end, %{}})
      data = Data.mark_save(data, @field, :saver, 0)
      assert Data.expire(data, 30_000).fields[@field].marks != %{}
      assert Data.expire(data, 30_001).fields[@field].marks == %{}

      saved =
        Ops.from_entry_blocks([
          entry_block("a", 1, 10, [child("a1", 11)]),
          entry_block("b", 2, 20),
          entry_block("n", 3, 30)
        ])

      {:ok, data, []} = Data.rebase(Data.expire(data, 60_000), @field, saved, {:client, :saver})
      state = Data.state(data, @field)
      assert state.order == ["a", "b", "n"]
      assert state.statuses["n"] == :persisted
    end

    test "the session keeps row ids only for blocks with unsaved work" do
      with_refs = fn uid, eb_id, block_id, refs ->
        %{id: eb_id, block: %{uid: uid, id: block_id, children: [], refs: refs}}
      end

      loaded =
        Ops.from_entry_blocks([
          with_refs.("a", 1, 10, [%{id: 100, uid: "ra"}]),
          with_refs.("b", 2, 20, [%{id: 200, uid: "rb"}])
        ])

      assert map_size(loaded.rel_ids) == 2
      {:seeded, data} = Data.join(Data.new(1), @field, loaded, loaded)
      assert Data.state(data, @field).rel_ids == %{}
      assert data.fields[@field].base.rel_ids == %{}

      # a new block is saved while it has unsaved work: its rows' ids stay,
      # since ops made before the save name them by uid
      {:ok, data} = Data.apply_op(data, @field, {:insert, "n", :end, %{}})
      data = Data.mark_save(data, @field, :saver, 0)

      saved =
        Ops.from_entry_blocks([
          with_refs.("a", 1, 10, [%{id: 100, uid: "ra"}]),
          with_refs.("b", 2, 20, [%{id: 200, uid: "rb"}]),
          with_refs.("n", 3, 30, [%{id: 300, uid: "rn"}])
        ])

      {:ok, data, []} = Data.rebase(data, @field, saved, {:client, :saver})
      assert Data.state(data, @field).rel_ids == %{"n" => %{{"refs", "rn"} => 300}}
    end

    test "a save that never rebases stops keeping the op log" do
      data = Data.new(1)
      {:seeded, data} = Data.join(data, @field, rows(), rows())
      data = Data.mark_save(data, @field, :client, 0)
      {:ok, data} = Data.apply_op(data, @field, anchor("b", "x"))
      assert [_] = data.fields[@field].log

      data = Data.expire(data, 10 * 60_000)
      assert data.fields[@field].marks == %{}
      assert data.fields[@field].log == []
    end

    test "a save's rebase finds the revision it read by the saving process" do
      data = Data.new(1)
      {:seeded, data} = Data.join(data, @field, rows(), rows())
      {:ok, data} = Data.apply_op(data, @field, {:insert, "saved", :end, %{}})
      data = Data.mark_save(data, @field, :saver, 0)
      {:ok, data} = Data.apply_op(data, @field, anchor("a", "after the read"))

      saved_rows =
        Ops.from_entry_blocks([
          entry_block("a", 1, 10, [child("a1", 11)]),
          entry_block("b", 2, 20),
          entry_block("saved", 9, 90)
        ])

      {:ok, data, []} = Data.rebase(data, @field, saved_rows, {:client, :saver})
      state = Data.state(data, @field)
      assert state.statuses["saved"] == :persisted
      assert state.diffs["a"]["block"]["anchor"] == "after the read"
    end
  end

  describe "tenancy" do
    setup do
      put_test_env(:tenancy_mode, :multi)
      on_exit(fn -> Tenant.put_prefix(nil) end)
      :ok
    end

    test "the starting process's site is part of the key and set in the session" do
      id = System.unique_integer([:positive])

      Tenant.put_prefix("tenant_acme_production")
      acme = EditSession.ref(Brando.Pages.Page, id)
      {:ok, %{session: acme_session}} = EditSession.join(acme, @field, {rows(), rows()})

      Tenant.put_prefix("tenant_beta_production")
      beta = EditSession.ref(Brando.Pages.Page, id)
      {:ok, %{session: beta_session}} = EditSession.join(beta, @field, {rows(), rows()})

      assert acme_session != beta_session
      assert acme.topic != beta.topic
      assert acme.topic =~ "tenant_acme_production"

      {:dictionary, dictionary} = Process.info(acme_session, :dictionary)
      assert "tenant_acme_production" in Keyword.values(dictionary)
      {:dictionary, dictionary} = Process.info(beta_session, :dictionary)
      assert "tenant_beta_production" in Keyword.values(dictionary)
    end
  end

  defp unlink_and_kill(pid) do
    Process.unlink(pid)
    Process.exit(pid, :kill)
  end

  defp wait_until(fun, tries \\ 100) do
    cond do
      fun.() -> :ok
      tries == 0 -> flunk("condition never held")
      true -> Process.sleep(10) && wait_until(fun, tries - 1)
    end
  end
end

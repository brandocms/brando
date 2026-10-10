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
      assert_receive {:edit_session, @field, %{kind: :rebase, reason: :rows_read}}

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
    # The grace period leaves room for a loaded machine: with 80 ms, the
    # editor coming back sometimes joined after it had run out (a flake in
    # the hunt for another one).
    test "the session stops a grace period after its last editor leaves" do
      put_test_env(EditSession, grace_period: 600)
      ref = new_ref()
      {a, info} = editor(ref)
      session = info.session
      monitor = Process.monitor(session)

      unlink_and_kill(a)

      # Someone comes back within the grace period: the session stays, past
      # the end of the period it was in.
      {b, _} = editor(ref)
      refute_receive {:DOWN, ^monitor, _, _, _}, 800
      assert EditSession.whereis(ref) == session

      unlink_and_kill(b)
      assert_receive {:DOWN, ^monitor, :process, ^session, :normal}, 2_000
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

    # The rows with block "a" holding `relations` (`table_rows: [5, 6]`).
    defp rows_with(relations) do
      named = %{table_rows: :sync_uid, refs: :uid, vars: :key}

      block =
        Enum.reduce(relations, %{uid: "a", id: 10, children: []}, fn {key, ids}, block ->
          Map.put(block, key, Enum.map(ids, &Map.put(%{id: &1}, named[key], "#{key}-#{&1}")))
        end)

      Ops.from_entry_blocks([%{id: 1, block: block}, entry_block("b", 2, 20)])
    end

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

    # Follow-up: a save slower than the mark's 30 seconds rebased as a carry,
    # which showed what it had saved as unsaved changes.
    test "a slow save keeps its mark until it is done, and its saved changes are not unsaved" do
      base = rows()
      {:seeded, data} = Data.join(Data.new(1), @field, base, base)
      {:ok, data} = Data.apply_op(data, @field, anchor("b", "saved by the slow save"))
      data = Data.mark_save(data, @field, :saver, 0)
      {:ok, data} = Data.apply_op(data, @field, anchor("a", "typed while it ran"))

      # two minutes later, the save is still running
      data = Data.expire(data, 2 * 60_000)
      assert Map.has_key?(data.fields[@field].marks, :saver)

      saved = Ops.from_entry_blocks([entry_block("a", 1, 10, [child("a1", 11)]), entry_block("b", 2, 20)])
      {:ok, data, []} = Data.rebase(data, @field, saved, {:client, :saver}, 2 * 60_000)
      state = Data.state(data, @field)
      refute Map.has_key?(state.diffs, "b")
      assert state.diffs["a"]["block"]["anchor"] == "typed while it ran"
      assert data.fields[@field].marks == %{}
    end

    test "a failed save releases its mark, and one nothing clears expires after 15 minutes" do
      base = rows()
      {:seeded, data} = Data.join(Data.new(1), @field, base, base)
      data = data |> Data.mark_save(@field, :failed, 0) |> Data.mark_save(@field, :forgotten, 0)
      {:ok, data} = Data.apply_op(data, @field, anchor("a", "after the marks"))

      data = Data.release(data, :failed)
      assert Map.keys(data.fields[@field].marks) == [:forgotten]
      assert [_] = data.fields[@field].log

      assert Data.expire(data, 15 * 60_000).fields[@field].marks != %{}
      data = Data.expire(data, 15 * 60_000 + 1)
      assert data.fields[@field].marks == %{}
      assert data.fields[@field].log == []
    end

    test "a save that failed tells the session" do
      ref = new_ref()
      {:ok, info} = EditSession.join(ref, @field, {rows(), rows()})
      {:ok, _} = EditSession.fetch(info.session, @field, purpose: :save)
      assert Map.has_key?(:sys.get_state(info.session).data.fields[@field].marks, self())

      EditSession.save_failed(%Brando.Pages.Page{id: elem(ref.key, 2), language: nil})
      wait_until(fn -> :sys.get_state(info.session).data.fields[@field].marks == %{} end)
    end

    test "the session's state keeps row ids only for blocks with unsaved work, its base all of them" do
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
      # a rejoiner may name a row by the uid it had while new (`Data.merge_held/4`)
      assert data.fields[@field].base.rel_ids == loaded.rel_ids

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

      data = Data.expire(data, 16 * 60_000)
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

    # Audit F1 (10 Oct 2026): a dirty rejoin between a save's read and its
    # rebase cleared the log but kept the save's mark, so the rebase replayed
    # nothing onto the saved rows: the op after the read and the rejoiner's
    # work were both gone, with no conflict.
    test "a rejoin carrying work while a save is in flight keeps that work and later ops through the save's rebase" do
      base = rows()
      {:seeded, data} = Data.join(Data.new(1), @field, base, base)
      {:ok, data} = Data.apply_op(data, @field, anchor("a", "saved"))
      data = Data.mark_save(data, @field, :saver, 0)
      {:ok, data} = Data.apply_op(data, @field, anchor("a", "after the read"))

      {:ok, held} = Ops.apply_op(base, anchor("b", "rejoiner's work"))
      {{:merged, []}, data} = Data.join(data, @field, base, held)
      {:ok, data} = Data.apply_op(data, @field, {:update, "a1", %{"description" => "after the rejoin"}})

      {:ok, data, []} = Data.rebase(data, @field, base, {:client, :saver})
      state = Data.state(data, @field)
      assert state.diffs["a"]["block"]["anchor"] == "after the read"
      assert state.diffs["b"]["block"]["anchor"] == "rejoiner's work"
      assert state.diffs["a1"]["description"] == "after the rejoin"
      assert data.fields[@field].log == []
    end

    # The reviewer's follow-up to F1: carrying a rejoiner's root diff onto the
    # session replaced the root's diff, so another editor's change to a
    # different field of that root went, with no conflict.
    test "a rejoin carrying work on a root keeps the session's changes to its other fields" do
      base = rows()
      {:seeded, data} = Data.join(Data.new(1), @field, base, base)
      {:ok, data} = Data.apply_op(data, @field, {:set_field, "a", ["block", "description"], "A, after the crash", 0})

      {:ok, held} = Ops.apply_op(base, anchor("a", "held by B"))
      {{:merged, []}, data} = Data.join(data, @field, base, held)

      assert Data.state(data, @field).diffs["a"] == %{
               "block" => %{"description" => "A, after the crash", "anchor" => "held by B"}
             }
    end

    # A cell edit names its row in a list skeleton taken when it was made, so
    # the rejoiner's diff carries the rows as it had them. Rows the session
    # added or removed since stay that way.
    test "a rejoin carrying a row edit keeps the rows the session added and removed" do
      base = rows()
      {:seeded, data} = Data.join(Data.new(1), @field, base, base)
      rows_then = [%{"id" => 5}, %{"id" => 7}]
      added = %{"sync_uid" => "new", "cols" => "A's row"}

      {:ok, data} =
        Data.apply_op(
          data,
          @field,
          {:set_field, "a", ["block", "table_rows"], {:list, rows_then, [%{"id" => 5}, added]}, 0}
        )

      cell = ["block", {:at, "table_rows", {"id", 5}, rows_then}, "cols"]
      {:ok, held} = Ops.apply_op(base, {:set_field, "a", cell, "B's cell", 0})
      {{:merged, []}, data} = Data.join(data, @field, base, held)

      assert Data.state(data, @field).diffs["a"]["block"]["table_rows"] == [%{"id" => 5, "cols" => "B's cell"}, added]
    end

    # Sol audit: the save's rebase replayed the rejoiner's list as it held
    # it, onto rows that now include a row the save wrote; the next save
    # would delete that row.
    test "a save's rebase replays a rejoin with the rows the merge kept" do
      base = Ops.from_entry_blocks([entry_block("a", 1, 10), entry_block("b", 2, 20)])
      {:seeded, data} = Data.join(Data.new(1), @field, base, base)
      rows_then = [%{"id" => 5}]
      added = %{"sync_uid" => "new", "cols" => "A's row"}

      {:ok, data} =
        Data.apply_op(
          data,
          @field,
          {:set_field, "a", ["block", "table_rows"], {:list, rows_then, rows_then ++ [added]}, 0}
        )

      data = Data.mark_save(data, @field, :saver, 0)

      cell = ["block", {:at, "table_rows", {"id", 5}, rows_then}, "cols"]
      {:ok, held} = Ops.apply_op(base, {:set_field, "a", cell, "B's cell", 0})
      {{:merged, []}, data} = Data.join(data, @field, base, held)

      saved =
        Ops.from_entry_blocks([
          %{
            id: 1,
            block: %{uid: "a", id: 10, children: [], table_rows: [%{id: 5, sync_uid: "r5"}, %{id: 8, sync_uid: "new"}]}
          },
          entry_block("b", 2, 20)
        ])

      {:ok, data, []} = Data.rebase(data, @field, saved, {:client, :saver})
      {:ok, params} = Ops.materialize_root(Data.state(data, @field), "a")
      assert [%{"id" => 5, "cols" => "B's cell"}, %{"id" => 8}] = params["block"]["table_rows"]
    end

    # Review: the replayed rejoin held the merged lists whole, so rows the
    # save had just written came back as unsaved work.
    test "a save's rebase replays a rejoin without making the saved rows unsaved" do
      base = rows_with(table_rows: [5, 6])
      {:seeded, data} = Data.join(Data.new(1), @field, base, base)
      rows_then = [%{"id" => 5}, %{"id" => 6}]

      {:ok, data} =
        Data.apply_op(
          data,
          @field,
          {:set_field, "a", ["block", {:at, "table_rows", {"id", 5}, rows_then}, "cols"], "saved by A", 0}
        )

      data = Data.mark_save(data, @field, :saver, 0)

      {:ok, held} =
        Ops.apply_op(base, {:set_field, "a", ["block", {:at, "table_rows", {"id", 6}, rows_then}, "cols"], "B's cell", 0})

      {{:merged, []}, data} = Data.join(data, @field, base, held)

      {:ok, data, []} = Data.rebase(data, @field, base, {:client, :saver})

      assert Data.state(data, @field).diffs["a"]["block"]["table_rows"] == [
               %{"id" => 5},
               %{"id" => 6, "cols" => "B's cell"}
             ]
    end

    # Sol audit: the log matched the rejoiner's rows by the name it had for
    # them, so a row it named by sync uid, which the session names by id,
    # was logged without the rejoiner's change.
    test "a save's rebase replays a rejoiner's change to a row it named by sync uid" do
      rows_a = fn rows -> %{id: 1, block: %{uid: "a", id: 10, children: [], table_rows: rows}} end
      old = Ops.from_entry_blocks([rows_a.([%{id: 5, sync_uid: "r5"}]), entry_block("b", 2, 20)])

      base =
        Ops.from_entry_blocks([rows_a.([%{id: 5, sync_uid: "r5"}, %{id: 8, sync_uid: "new"}]), entry_block("b", 2, 20)])

      # the session names the rows of a block with unsaved work by id
      {:ok, seed} = Ops.apply_op(base, anchor("a", "A, saving"))
      {:seeded, data} = Data.join(Data.new(1), @field, base, seed)
      assert Data.state(data, @field).rel_ids["a"][{"table_rows", "new"}] == 8
      data = Data.mark_save(data, @field, :saver, 0)

      {:ok, held} =
        Ops.apply_op(
          old,
          {:update, "a", %{"block" => %{"table_rows" => [%{"id" => 5}, %{"sync_uid" => "new", "cols" => "B"}]}}}
        )

      {{:merged, []}, data} = Data.merge_held(data, @field, held, old)

      {:ok, data, []} = Data.rebase(data, @field, base, {:client, :saver})
      {:ok, params} = Ops.materialize_root(Data.state(data, @field), "a")
      assert [%{"id" => 5}, %{"id" => 8, "cols" => "B"}] = params["block"]["table_rows"]
    end

    # A row inside a row the rejoiner removed stays removed through the
    # save's replay, though the session changed it before the save read.
    test "a save's rebase replays a rejoin's removal inside a row" do
      base = rows_with(table_rows: [5])
      {:seeded, data} = Data.join(Data.new(1), @field, base, base)
      vars_then = [%{"id" => 51}, %{"id" => 52}]

      at_var = fn id ->
        ["block", {:at, "table_rows", {"id", 5}, [%{"id" => 5}]}, {:at, "vars", {"id", id}, vars_then}, "value"]
      end

      {:ok, data} = Data.apply_op(data, @field, {:set_field, "a", at_var.(52), "A, saving", 0})
      data = Data.mark_save(data, @field, :saver, 0)

      {:ok, held} =
        Ops.apply_op(
          base,
          {:update, "a", %{"block" => %{"table_rows" => [%{"id" => 5, "vars" => [%{"id" => 51, "value" => "B"}]}]}}}
        )

      {{:merged, []}, data} = Data.join(data, @field, base, held)
      assert [%{"id" => 5, "vars" => [_]}] = Data.state(data, @field).diffs["a"]["block"]["table_rows"]

      {:ok, data, []} = Data.rebase(data, @field, base, {:client, :saver})

      assert [%{"id" => 5, "vars" => [%{"id" => 51, "value" => "B"}]}] =
               Data.state(data, @field).diffs["a"]["block"]["table_rows"]
    end

    # Sol audit: the log passed maps inside a row through as the rejoiner
    # had them. The rows of a list in one (a gallery's objects) the session
    # added are kept through the save's replay.
    test "a save's rebase replays a rejoin with the rows of a list in a map inside a row" do
      base = rows_with(refs: [3])
      {:seeded, data} = Data.join(Data.new(1), @field, base, base)
      ref = fn objects -> %{"block" => %{"refs" => [%{"id" => 3, "gallery" => %{"gallery_objects" => objects}}]}} end

      {:ok, data} =
        Data.apply_op(data, @field, {:update, "a", ref.([%{"id" => 51}, %{"id" => 52, "caption" => "A"}, %{"id" => 53}])})

      data = Data.mark_save(data, @field, :saver, 0)

      {:ok, held} =
        Ops.apply_op(base, {:update, "a", ref.([%{"id" => 51, "caption" => "B"}, %{"id" => 52}, %{"id" => 53}])})

      {{:merged, []}, data} = Data.join(data, @field, base, held)

      {:ok, data, []} = Data.rebase(data, @field, base, {:client, :saver})

      assert [%{"gallery" => %{"gallery_objects" => [%{"id" => 51, "caption" => "B"}, %{"id" => 52}, %{"id" => 53}]}}] =
               Data.state(data, @field).diffs["a"]["block"]["refs"]
    end

    # Sol audit: the log indexed a list by identity even when two items are
    # named alike, which the merge takes whole.
    test "a save's rebase replays a rejoiner's list with items named alike as it had it" do
      base = rows_with(vars: [5])
      {:seeded, data} = Data.join(Data.new(1), @field, base, base)
      {:ok, data} = Data.apply_op(data, @field, anchor("a", "A, saving"))
      data = Data.mark_save(data, @field, :saver, 0)

      options = [%{"value" => "1", "label" => "One"}, %{"value" => "1", "label" => "Also one"}]
      {:ok, held} = Ops.apply_op(base, {:update, "a", %{"block" => %{"vars" => [%{"id" => 5, "options" => options}]}}})
      {{:merged, []}, data} = Data.join(data, @field, base, held)

      {:ok, data, []} = Data.rebase(data, @field, base, {:client, :saver})
      assert [%{"id" => 5, "options" => ^options}] = Data.state(data, @field).diffs["a"]["block"]["vars"]
    end

    # A rejoin as `BlockField.rejoin_session/1` makes it: with the rows the
    # editor loaded, not read again. Their blocks are the session's, so the
    # session takes the editor's work, but a row may have been saved since.
    defp table_rows_of(ids),
      do:
        Ops.from_entry_blocks([
          %{
            id: 1,
            block: %{
              uid: "a",
              id: 10,
              children: [],
              table_rows: Enum.map(ids, fn {id, sync} -> %{id: id, sync_uid: sync} end)
            }
          },
          entry_block("b", 2, 20)
        ])

    defp save_rows(session, ops, saved) do
      Enum.each(Enum.with_index(ops, 1), fn {op, seq} -> EditSession.submit(session, @field, op, seq) end)
      {:ok, _} = EditSession.fetch(session, @field, purpose: :save)
      {:ok, _} = EditSession.rebase(session, @field, saved, :own_save)
    end

    # As `BlockField.join_session/2` does: rows that are not the session's
    # are read again (`rows_now`), and the join moves the session onto them.
    defp rejoin_with_stale_rows(ref, loaded, held, rows_now \\ nil, opts \\ []) do
      Task.await(
        Task.async(fn ->
          case EditSession.join(ref, @field, {loaded, held}, opts) do
            {:error, :base_mismatch} when rows_now != nil ->
              EditSession.join(ref, @field, {rows_now, held}, [rebase: true, held_base: loaded] ++ opts)

            result ->
              result
          end
        end)
      )
    end

    # Review: a row saved while the rejoiner was away was deleted. Its
    # rows still had the same blocks, so the session took its list as the
    # rows were when it loaded them.
    test "a rejoin keeps a row saved while the rejoiner was away" do
      ref = new_ref()
      loaded = table_rows_of([{5, "r5"}])
      rows_then = [%{"id" => 5}]

      # the session was replaced; A came back first, added a row and saved
      {:ok, a} = EditSession.join(ref, @field, {loaded, loaded})
      add = {:set_field, "a", ["block", "table_rows"], {:list, rows_then, rows_then ++ [%{"sync_uid" => "r8"}]}, 0}
      saved = table_rows_of([{5, "r5"}, {8, "r8"}])
      save_rows(a.session, [add], saved)

      cell = ["block", {:at, "table_rows", {"id", 5}, rows_then}, "cols"]
      {:ok, held} = Ops.apply_op(loaded, {:set_field, "a", cell, "B's cell", 0})
      assert {:ok, %{state: state}} = rejoin_with_stale_rows(ref, loaded, held, saved)

      {:ok, params} = Ops.materialize_root(state, "a")
      assert [%{"id" => 5, "cols" => "B's cell"}, %{"id" => 8}] = params["block"]["table_rows"]
    end

    # Review: a new row the rejoiner held, which a save has since given an
    # id, came in twice (or was deleted and inserted again).
    test "a rejoin matches a new row it held with the row a save made of it" do
      ref = new_ref()
      loaded = table_rows_of([{5, "r5"}])
      rows_then = [%{"id" => 5}]

      add = fn cols ->
        {:set_field, "a", ["block", "table_rows"],
         {:list, rows_then, rows_then ++ [%{"sync_uid" => "new", "cols" => cols}]}, 0}
      end

      {:ok, a} = EditSession.join(ref, @field, {loaded, loaded})
      saved = table_rows_of([{5, "r5"}, {8, "new"}])
      save_rows(a.session, [add.("A")], saved)

      {:ok, held} = Ops.apply_op(loaded, add.("B"))
      assert {:ok, %{state: state}} = rejoin_with_stale_rows(ref, loaded, held, saved)

      {:ok, params} = Ops.materialize_root(state, "a")
      assert [%{"id" => 5}, %{"id" => 8, "cols" => "B"}] = params["block"]["table_rows"]
    end

    # Sol audit: a session seeded from the rows after the save named only
    # the rows of blocks with unsaved work, so the rejoiner's new row was
    # not matched with the row the save made of it.
    test "a rejoin matches a new row it held with a saved row, in a session seeded after the save" do
      ref = new_ref()
      loaded = table_rows_of([{5, "r5"}])
      rows_then = [%{"id" => 5}]

      # C seeds the replaced session from the rows A's save wrote
      saved = table_rows_of([{5, "r5"}, {8, "new"}])
      {:ok, %{seeded?: true}} = EditSession.join(ref, @field, {saved, saved})

      add =
        {:set_field, "a", ["block", "table_rows"],
         {:list, rows_then, rows_then ++ [%{"sync_uid" => "new", "cols" => "B"}]}, 0}

      {:ok, held} = Ops.apply_op(loaded, add)
      assert {:ok, %{state: state}} = rejoin_with_stale_rows(ref, loaded, held, saved)

      {:ok, params} = Ops.materialize_root(state, "a")
      assert [%{"id" => 5}, %{"id" => 8, "cols" => "B"}] = params["block"]["table_rows"]
    end

    # Sol audit: the save's replay of that rejoin named the row as the
    # rejoiner did, and logged it without the rejoiner's change.
    test "a save's rebase keeps a late rejoiner's change to a row a save made of its new row" do
      ref = new_ref()
      loaded = table_rows_of([{5, "r5"}])
      rows_then = [%{"id" => 5}]
      saved = table_rows_of([{5, "r5"}, {8, "new"}])

      {:ok, c} = EditSession.join(ref, @field, {saved, saved})
      EditSession.submit(c.session, @field, anchor("b", "C, saving"), 1)
      {:ok, _} = EditSession.fetch(c.session, @field, purpose: :save)

      add =
        {:set_field, "a", ["block", "table_rows"],
         {:list, rows_then, rows_then ++ [%{"sync_uid" => "new", "cols" => "B"}]}, 0}

      {:ok, held} = Ops.apply_op(loaded, add)
      assert {:ok, _} = rejoin_with_stale_rows(ref, loaded, held, saved)

      assert {:ok, %{state: state}} = EditSession.rebase(c.session, @field, saved, :own_save)
      {:ok, params} = Ops.materialize_root(state, "a")
      assert [%{"id" => 5}, %{"id" => 8, "cols" => "B"}] = params["block"]["table_rows"]
    end

    # Review: a join compared blocks only, so an editor with older rows
    # (that never read a save's added row) could seed or join a session as
    # if its rows were the session's, and a later rejoin merged against them.
    test "a joiner whose rows differ from the session's in their rows reads them again" do
      ref = new_ref()
      old_rows = table_rows_of([{5, "r5"}])
      saved = table_rows_of([{5, "r5"}, {8, "r8"}])

      # B, still on the rows before A's save, seeds a replacement session
      {:ok, _} = EditSession.join(ref, @field, {old_rows, old_rows})

      # C loaded the saved rows and changed row 8
      cell = ["block", {:at, "table_rows", {"id", 8}, [%{"id" => 5}, %{"id" => 8}]}, "cols"]
      {:ok, held} = Ops.apply_op(saved, {:set_field, "a", cell, "C's cell", 0})
      assert {:error, :base_mismatch} = rejoin_with_stale_rows(ref, saved, held)

      # it reads the rows again (the same) and moves the session onto them
      assert {:ok, %{state: state}} =
               Task.await(
                 Task.async(fn -> EditSession.join(ref, @field, {saved, held}, rebase: true, held_base: saved) end)
               )

      {:ok, params} = Ops.materialize_root(state, "a")
      assert [%{"id" => 5}, %{"id" => 8, "cols" => "C's cell"}] = params["block"]["table_rows"]
    end

    # Both editors held the same new block when the session died; the one
    # who came back second held a different version of it. The session
    # keeps the first's, and gives the rejoiner back its own as a copy.
    test "a rejoiner holding another version of a new block the session has gets it back as a copy" do
      ref = new_ref()
      base = rows()
      insert = fn text -> {:insert, "n", 1, %{"block" => %{"uid" => "n", "description" => text}}} end
      {:ok, seed} = Ops.apply_op(base, insert.("A's version"))
      {:ok, _} = EditSession.join(ref, @field, {base, seed})

      {:ok, held} = Ops.apply_op(base, insert.("B's version"))
      {:ok, held} = Ops.apply_op(held, {:insert_child, "n", "nc", 0, %{"uid" => "nc"}})
      assert {:ok, info} = rejoin_with_stale_rows(ref, base, held, nil, changed: ["n"])

      assert info.state.diffs["n"]["block"]["description"] == "A's version"
      assert [%{group: "n", kept: "n-kept", uids: uids, copy?: true}] = info.rescues
      assert Enum.sort(uids) == ["n", "nc"]
    end

    test "a copy a rejoiner brings back during another editor's save stays through that save's rebase" do
      ref = new_ref()
      base = rows()
      insert = fn uid, text -> {:insert, uid, 1, %{"block" => %{"uid" => uid, "description" => text}}} end
      {:ok, seed} = Ops.apply_op(base, insert.("n", "A's version"))
      {:ok, a} = EditSession.join(ref, @field, {base, seed})
      {:ok, _} = EditSession.fetch(a.session, @field, purpose: :save)

      {:ok, held} = Ops.apply_op(base, insert.("n", "B's version"))

      task =
        Task.async(fn ->
          {:ok, info} = EditSession.join(ref, @field, {base, held}, changed: ["n"])
          [%{kept: kept}] = info.rescues
          EditSession.submit(info.session, @field, insert.(kept, "B's version"), 1)
          {:ok, _} = EditSession.fetch(info.session, @field)
          kept
        end)

      kept = Task.await(task)

      saved =
        Ops.from_entry_blocks([
          entry_block("a", 1, 10, [child("a1", 11)]),
          entry_block("n", 9, 90),
          entry_block("b", 2, 20)
        ])

      assert {:ok, %{state: state}} = EditSession.rebase(a.session, @field, saved, :own_save)
      assert state.statuses["n"] == :persisted
      assert state.statuses[kept] == :inserted
      assert state.diffs[kept]["block"]["description"] == "B's version"
    end

    # Sol audit: two rejoiners were both given `n-kept`; the second insert
    # was turned away and its version lost.
    test "two rejoiners with their own versions of a new block get copies under different uids" do
      ref = new_ref()
      base = rows()
      insert = fn text -> {:insert, "n", 1, %{"block" => %{"uid" => "n", "description" => text}}} end
      {:ok, seed} = Ops.apply_op(base, insert.("A's version"))
      {:ok, _} = EditSession.join(ref, @field, {base, seed})

      kept =
        for text <- ["B's version", "C's version"] do
          {:ok, held} = Ops.apply_op(base, insert.(text))
          parent = self()

          spawn(fn ->
            {:ok, info} = EditSession.join(ref, @field, {base, held}, changed: ["n"])
            send(parent, {:kept, Enum.map(info.rescues, & &1.kept)})
            Process.sleep(:infinity)
          end)

          assert_receive {:kept, [uid]}
          uid
        end

      assert kept == ["n-kept", "n-kept-2"]
    end

    # Sol audit: a block saved before the rejoin is a row with no diff in
    # the session, so any held version looked different from it.
    test "a rejoiner holding a new block the session has saved since gets no copy" do
      ref = new_ref()
      base = rows()
      {:ok, held} = Ops.apply_op(base, {:insert, "n", 1, %{"block" => %{"uid" => "n", "description" => "same"}}})

      saved =
        Ops.from_entry_blocks([
          entry_block("a", 1, 10, [child("a1", 11)]),
          entry_block("n", 9, 90),
          entry_block("b", 2, 20)
        ])

      {:ok, _} = EditSession.join(ref, @field, {saved, saved})

      assert {:ok, info} = EditSession.join(ref, @field, {saved, held}, held_base: base, rebase: true, changed: ["n"])
      assert info.rescues == []
    end

    # Sol audit: a block a rejoin carried into a session seeded from the
    # rows is stored as the carry made it, which a raw comparison took for
    # another version: the rejoiner, and the next one holding the same,
    # were given copies of it.
    test "rejoiners holding the same new block a fresh session did not have get no copies" do
      ref = new_ref()
      base = rows()
      {:ok, _} = EditSession.join(ref, @field, {base, base})
      {:ok, held} = Ops.apply_op(base, {:insert, "n", 1, %{"block" => %{"uid" => "n", "description" => "same"}}})

      for _editor <- [:a, :b] do
        assert {:ok, info} = rejoin_with_stale_rows(ref, base, held, nil, changed: ["n"])
        assert info.rescues == []
        assert info.state.statuses["n"] == :inserted
      end
    end

    # Sol audit: only a copy's own uid was reserved, so a copy of one of its
    # children, asked of another rejoiner, could take a uid it would take.
    test "a copy's children's uids are reserved for it" do
      ref = new_ref()
      base = rows()
      insert = fn text -> {:insert, "n", 1, %{"block" => %{"uid" => "n", "description" => text}}} end
      child = fn ops, text -> Ops.apply_op(ops, {:insert_child, "n", "c", 0, %{"uid" => "c", "description" => text}}) end

      {:ok, seed} = Ops.apply_op(base, insert.("A's version"))
      {:ok, seed} = child.(seed, "A's child")
      {:ok, _} = EditSession.join(ref, @field, {base, seed})

      {:ok, b_held} = Ops.apply_op(base, insert.("B's version"))
      {:ok, b_held} = child.(b_held, "B's child")
      assert {:ok, %{rescues: [%{kept: "n-kept"}]}} = rejoin_with_stale_rows(ref, base, b_held, nil, changed: ["n", "c"])

      # C moved the child under a saved block and changed it
      {:ok, c_held} = Ops.apply_op(base, insert.("A's version"))
      {:ok, c_held} = child.(c_held, "C's child")
      {:ok, c_held} = Ops.apply_op(c_held, {:move_to_parent, "c", "a", :end})
      assert {:ok, %{rescues: rescues}} = rejoin_with_stale_rows(ref, base, c_held, nil, changed: ["c"])
      assert %{kept: kept} = Enum.find(rescues, &(&1.group == "c"))
      refute kept == "c-kept"
    end

    # Sol audit: a block whose children were all removed holds an empty list
    # of them, which a carry does not store.
    test "a new block whose children were all removed is the same without them" do
      ref = new_ref()
      base = rows()
      {:ok, _} = EditSession.join(ref, @field, {base, base})
      {:ok, held} = Ops.apply_op(base, {:insert, "n", 1, %{"block" => %{"uid" => "n"}}})
      {:ok, held} = Ops.apply_op(held, {:insert_child, "n", "c", 0, %{"uid" => "c"}})
      {:ok, held} = Ops.apply_op(held, {:delete, "c"})

      for _editor <- [:a, :b] do
        assert {:ok, %{rescues: []}} = rejoin_with_stale_rows(ref, base, held, nil, changed: ["n"])
      end
    end

    # Review: an editor who never changed a new block, coming back after
    # the one who did, held the older version, and was given a copy of it.
    test "a rejoiner that did not change a new block itself gets no copy of its version" do
      ref = new_ref()
      base = rows()
      insert = fn text -> {:insert, "n", 1, %{"block" => %{"uid" => "n", "description" => text}}} end
      {:ok, seed} = Ops.apply_op(base, insert.("B's change"))
      {:ok, _} = EditSession.join(ref, @field, {base, seed})

      {:ok, held} = Ops.apply_op(base, insert.("as it was"))
      {:ok, held} = Ops.apply_op(held, anchor("a", "A's own work"))
      assert {:ok, info} = rejoin_with_stale_rows(ref, base, held, nil, changed: ["a"])
      assert info.rescues == []
      assert info.state.diffs["n"]["block"]["description"] == "B's change"
    end

    # Review: a pending delete, restore or recovery copy named no block, so
    # a version they made was not the rejoiner's own, and was dropped
    # without a word when the session died before confirming it.
    test "a replica's changes name the blocks its pending deletes, restores and carries touched" do
      base = rows()
      {:ok, state} = Ops.apply_op(base, {:insert, "n", 1, %{"block" => %{"uid" => "n"}}})
      {:ok, state} = Ops.apply_op(state, {:insert_child, "n", "c", 0, %{"uid" => "c"}})
      snapshot = Ops.bin_snapshot(state, "c")
      {:ok, copy} = Ops.apply_op(state, {:update, "n", %{"block" => %{"description" => "recovered"}}})

      replica = Replica.new(nil, %{session: nil, epoch: 1, rev: 0, state: state}, nil)

      for {op, named} <- [
            {{:delete, "c"}, ["c", "n"]},
            {{:restore, snapshot}, ["c", "n"]},
            {{:carry, copy, base}, ["n"]}
          ] do
        {replica, _} = Replica.local(replica, op)
        assert MapSet.subset?(MapSet.new(named), MapSet.new(Replica.changed(replica)))
      end
    end

    test "a rejoiner holding the same version of a new block the session has gets no copy" do
      ref = new_ref()
      base = rows()
      {:ok, held} = Ops.apply_op(base, {:insert, "n", 1, %{"block" => %{"uid" => "n", "description" => "same"}}})
      {:ok, _} = EditSession.join(ref, @field, {base, held})
      {:ok, held} = Ops.apply_op(held, anchor("a", "B's other work"))

      assert {:ok, info} = rejoin_with_stale_rows(ref, base, held)
      assert info.rescues == []
      assert info.state.diffs["a"]["block"]["anchor"] == "B's other work"
    end

    test "a rejoin carrying work after a save's read is kept by that save's rebase, on the session" do
      ref = new_ref()
      Phoenix.PubSub.subscribe(Brando.pubsub(), ref.topic)
      base = rows()

      # The session was replaced; A came back first and seeded it.
      {:ok, a} = EditSession.join(ref, @field, {base, base})
      session = a.session
      EditSession.submit(session, @field, anchor("a", "saved by A"), 1)
      {:ok, %{state: read}} = EditSession.fetch(session, @field, purpose: :save)
      assert read.diffs["a"]["block"]["anchor"] == "saved by A"

      # C types while A's save runs; then B handles the session's exit late
      # and comes back with work it held.
      c =
        Task.async(fn ->
          {:ok, _} = EditSession.join(ref, @field, {base, base})
          EditSession.submit(session, @field, {:update, "a1", %{"description" => "C, during the save"}}, 1)
          EditSession.fetch(session, @field)
        end)

      {:ok, _} = Task.await(c)
      {:ok, held} = Ops.apply_op(base, anchor("b", "held by B"))
      {:ok, b} = Task.await(Task.async(fn -> EditSession.join(ref, @field, {base, held}) end))
      assert b.state.diffs["b"]["block"]["anchor"] == "held by B"

      # the rows A wrote: same blocks, its change is in them now
      assert {:ok, after_save} = EditSession.rebase(session, @field, rows(), :own_save)

      for state <- [after_save.state, elem(session_state(ref), 0)] do
        assert state.diffs["a"] in [nil, %{}]
        assert state.diffs["a1"]["description"] == "C, during the save"
        assert state.diffs["b"]["block"]["anchor"] == "held by B"
      end

      assert_receive {:edit_session, @field, %{kind: :rebase, reason: :saved, conflicts: []}}
    end
  end

  # Follow-up, round 2: who brings back unsaved work in blocks a write
  # removed. The session asks one editor per removed block, never the one
  # whose own write or join caused the rebase, and asks the next one if it
  # does not answer or leaves.
  describe "rescues" do
    setup do
      previous = Application.get_env(:brando, EditSession, [])
      Application.put_env(:brando, EditSession, Keyword.put(previous, :rescue_timeout, 500))
      on_exit(fn -> Application.put_env(:brando, EditSession, previous) end)
      :ok
    end

    defp without_b, do: Ops.from_entry_blocks([entry_block("a", 1, 10, [child("a1", 11)])])

    # `p1` worked in "b", `p2` is here too; then the rows lose "b".
    defp removed_with_work do
      ref = new_ref()
      Phoenix.PubSub.subscribe(Brando.pubsub(), ref.topic)
      {p1, info} = editor(ref)
      {p2, _} = editor(ref)
      send(p1, {:local, anchor("b", "p1's work")})
      assert_receive {:edit_session, @field, %{kind: :op, origin: {^p1, _}}}
      {ref, info.session, p1, p2}
    end

    test "the editor who worked in the block is asked, and everyone hears once the copy is there" do
      {_ref, session, p1, _p2} = removed_with_work()
      {:ok, _} = EditSession.rebase(session, @field, without_b(), :carry)

      assert_receive {:edit_session, @field, %{kind: :rebase, rescues: [pending]}}
      assert %{group: "b", kept: "b-kept", uids: ["b"], rescuer: ^p1, owners: [^p1], orphan?: false} = pending

      send(p1, {:local, {:insert, "b-kept", :end, %{}}})
      assert_receive {:edit_session, @field, %{kind: :rescued, group: "b", ok?: true, owners: [^p1], orphan?: false}}
    end

    test "an editor who says it is done without the copy there is replaced by the next" do
      {_ref, session, p1, p2} = removed_with_work()
      {:ok, _} = EditSession.rebase(session, @field, without_b(), :carry)
      assert_receive {:edit_session, @field, %{kind: :rebase, rescues: [%{rescuer: ^p1}]}}

      # the insert was turned away (its parent went meanwhile, say)
      :ok = GenServer.cast(session, {:rescued, p1, @field, "b"})
      assert_receive {:edit_session, @field, %{kind: :rescue, group: "b", rescuer: ^p2}}, 3_000
    end

    test "an editor who does not answer in time is replaced by the next" do
      {ref, session, p1, p2} = removed_with_work()
      {:ok, _} = EditSession.rebase(session, @field, without_b(), :carry)
      assert_receive {:edit_session, @field, %{kind: :rebase, rescues: [%{rescuer: ^p1}]}}

      # one who joins after the work was removed never saw it, and is not told
      {late, _} = editor(ref, without_b())

      assert_receive {:edit_session, @field, %{kind: :rescue, group: "b", rescuer: ^p2}}, 3_000
      send(p2, {:local, {:insert, "b-kept", :end, %{}}})
      assert_receive {:edit_session, @field, %{kind: :rescued, group: "b", ok?: true, present: present}}
      assert Enum.sort(present) == Enum.sort([p1, p2])
      refute late in present
    end

    test "a slow editor's copy landing after the next was asked counts, and no failure follows" do
      {_ref, session, p1, p2} = removed_with_work()
      {:ok, _} = EditSession.rebase(session, @field, without_b(), :carry)
      assert_receive {:edit_session, @field, %{kind: :rebase, rescues: [%{rescuer: ^p1}]}}
      assert_receive {:edit_session, @field, %{kind: :rescue, rescuer: ^p2}}, 3_000

      # p2 has no copy to make; p1's insert lands late
      :ok = GenServer.cast(session, {:rescued, p2, @field, "b"})
      send(p1, {:local, {:insert, "b-kept", :end, %{}}})
      assert_receive {:edit_session, @field, %{kind: :rescued, group: "b", ok?: true}}, 3_000
      refute_receive {:edit_session, @field, %{kind: :rescued, ok?: false}}, 1_200
    end

    test "an editor who leaves is replaced at once, and with nobody left the work is reported lost" do
      {ref, session, p1, p2} = removed_with_work()
      # one who may only look keeps the session open, and cannot be asked
      {_watcher, _} = editor(ref, rows(), read_only: true)
      {:ok, _} = EditSession.rebase(session, @field, without_b(), :carry)
      assert_receive {:edit_session, @field, %{kind: :rebase, rescues: [%{rescuer: ^p1}]}}

      unlink_and_kill(p1)
      assert_receive {:edit_session, @field, %{kind: :rescue, group: "b", rescuer: ^p2}}, 3_000

      unlink_and_kill(p2)
      assert_receive {:edit_session, @field, %{kind: :rescued, group: "b", ok?: false, orphan?: false}}, 3_000
    end

    # Round 3: the origin of an outside write was never asked, so the only
    # editor, activating a revision from its own drawer, lost its work in a
    # block the revision lacks without a word.
    test "an editor whose own process wrote outside the editor is asked too" do
      ref = new_ref()
      Phoenix.PubSub.subscribe(Brando.pubsub(), ref.topic)
      {:ok, info} = EditSession.join(ref, @field, {rows(), rows()})
      EditSession.submit(info.session, @field, anchor("b", "my work"), 1)
      assert_receive {:edit_session, @field, %{kind: :op}}
      me = self()

      # what `sync_saved/1` does from the same process after the write
      {:ok, _} = EditSession.rebase(info.session, @field, without_b(), :carry)
      assert_receive {:edit_session, @field, %{kind: :rebase, rescues: [%{group: "b", rescuer: ^me}]}}
    end

    test "when nobody can bring the work back, those it concerns are told at once" do
      ref = new_ref()
      Phoenix.PubSub.subscribe(Brando.pubsub(), ref.topic)
      {:ok, info} = EditSession.join(ref, @field, {rows(), rows()})
      EditSession.submit(info.session, @field, anchor("b", "my work"), 1)
      assert_receive {:edit_session, @field, %{kind: :op}}
      me = self()

      # the replica's own rebase: it moves on with the reply, and is the only editor
      {:ok, _} = EditSession.rebase(info.session, @field, without_b(), :carry, replica: true)
      assert_receive {:edit_session, @field, %{kind: :rebase, rescues: []}}
      assert_receive {:edit_session, @field, %{kind: :rescued, group: "b", ok?: false, owners: [^me]}}
    end

    test "the editor whose join removed the block is never asked: its replica moved on with the reply" do
      ref = new_ref()
      Phoenix.PubSub.subscribe(Brando.pubsub(), ref.topic)
      {other, _} = editor(ref)
      {gone, _} = editor(ref)
      send(gone, {:local, anchor("b", "work of an editor who left")})
      assert_receive {:edit_session, @field, %{kind: :op, origin: {^gone, _}}}
      unlink_and_kill(gone)

      # a joiner whose newer rows lack "b"
      {joiner, _} = editor(ref, without_b(), rebase: true)
      assert_receive {:edit_session, @field, %{kind: :rebase, origin: ^joiner, rescues: [pending]}}, 1_000
      assert %{group: "b", rescuer: ^other, orphan?: true} = pending
    end

    test "work in two children of one removed block is one group, brought back by one editor" do
      ref = new_ref()
      Phoenix.PubSub.subscribe(Brando.pubsub(), ref.topic)
      two = Ops.from_entry_blocks([entry_block("a", 1, 10, [child("a1", 11), child("a2", 12)]), entry_block("b", 2, 20)])
      {p1, info} = editor(ref, two)
      {p2, _} = editor(ref, two)
      send(p1, {:local, {:update, "a1", %{"description" => "p1"}}})
      send(p2, {:local, {:update, "a2", %{"description" => "p2"}}})
      assert_receive {:edit_session, @field, %{kind: :op, origin: {^p1, _}}}
      assert_receive {:edit_session, @field, %{kind: :op, origin: {^p2, _}}}

      {:ok, _} = EditSession.rebase(info.session, @field, Ops.from_entry_blocks([entry_block("b", 2, 20)]), :carry)
      assert_receive {:edit_session, @field, %{kind: :rebase, rescues: [pending]}}
      assert %{group: "a", rescuer: rescuer, owners: owners} = pending
      assert Enum.sort(pending.uids) == ["a1", "a2"]
      assert Enum.sort(owners) == Enum.sort([p1, p2])
      assert rescuer in [p1, p2]
    end

    # The review's Z probe: a proposal removed "b", "b" was brought back as
    # "b-kept", the proposal was undone so "b" returned while "b-kept"
    # stayed, and the editor worked in "b" again before another write
    # removed it. The earlier copy settled the new rescue at once, nothing
    # was inserted, the new work was lost and everyone heard it was back.
    test "a group removed again while its earlier copy is still there gets a copy of its own" do
      {_ref, session, p1, p2} = removed_with_work()
      send(p1, {:local, {:insert, "b-kept", :end, %{}}})
      assert_receive {:edit_session, @field, %{kind: :op, origin: {^p1, _}}}

      {:ok, _} = EditSession.rebase(session, @field, without_b(), :carry)
      assert_receive {:edit_session, @field, %{kind: :rebase, rescues: [%{group: "b", kept: "b-kept-2", rescuer: ^p1}]}}

      # any op settles nothing while the new copy is missing
      send(p2, {:local, anchor("a", "unrelated")})
      assert_receive {:edit_session, @field, %{kind: :op, origin: {^p2, _}}}
      refute_receive {:edit_session, @field, %{kind: :rescued}}, 100

      send(p1, {:local, {:insert, "b-kept-2", :end, %{}}})
      assert_receive {:edit_session, @field, %{kind: :rescued, group: "b", ok?: true}}
    end

    test "a copy whose blocks would take a uid an earlier copy has takes the next suffix" do
      ref = new_ref()
      Phoenix.PubSub.subscribe(Brando.pubsub(), ref.topic)
      {p1, info} = editor(ref)
      {_watcher, _} = editor(ref, rows(), read_only: true)
      # an earlier copy of "a1" is here; "a" itself has none
      send(p1, {:local, {:insert, "a1-kept", :end, %{}}})
      send(p1, {:local, {:update, "a1", %{"description" => "p1"}}})
      assert_receive {:edit_session, @field, %{kind: :op, origin: {^p1, 2}}}

      {:ok, _} = EditSession.rebase(info.session, @field, Ops.from_entry_blocks([entry_block("b", 2, 20)]), :carry)
      assert_receive {:edit_session, @field, %{kind: :rebase, rescues: [%{group: "a", kept: "a-kept-2"}]}}
    end
  end

  # The flake hunt: an editor whose session was killed rejoins as soon as
  # its :DOWN arrives, which can be before the Registry has dropped the dead
  # session. The lookup returned the dead pid, the join's retry did too,
  # and the LiveView crashed.
  test "a session killed a moment ago is replaced, even before the registry has noticed" do
    ref = new_ref()
    {:ok, info} = EditSession.join(ref, @field, {rows(), rows()})
    partition = Module.concat(Brando.EditSession.Registry, "PIDPartition0")
    assert is_pid(Process.whereis(partition))

    # the registry cannot clean up while it is suspended
    :sys.suspend(partition)

    try do
      Process.exit(info.session, :kill)
      wait_until(fn -> not Process.alive?(info.session) end)
      assert EditSession.whereis(ref) == nil
      assert {:ok, rejoined} = EditSession.join(ref, @field, {rows(), rows()})
      assert rejoined.session != info.session
    after
      :sys.resume(partition)
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

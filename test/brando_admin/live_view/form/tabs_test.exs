defmodule BrandoAdmin.LiveView.Form.TabsTest do
  use ExUnit.Case, async: true

  alias BrandoAdmin.LiveView.Form.Tabs

  defp meta(tab, claim, opened_at \\ 100, pid \\ nil),
    do: %{
      tab: tab,
      pid: pid || spawn(fn -> :ok end),
      claim: claim,
      auto: true,
      opened_at: opened_at,
      joined: System.unique_integer([:monotonic, :positive])
    }

  defp state(meta, mode, opts \\ []) do
    %{
      meta: meta,
      mode: mode,
      edited?: Keyword.get(opts, :edited?, mode in [:editing, :released]),
      others?: Keyword.get(opts, :others?, false),
      closed?: false,
      other: nil,
      from: Keyword.get(opts, :from)
    }
  end

  describe "editor/1" do
    test "the highest claim edits, the tab id breaking a tie, and 0 claims nothing" do
      a = meta("a", 2)
      b = meta("b", 2)
      c = meta("c", 1)

      assert Tabs.editor([c, a, b]) == b
      assert Tabs.editor([meta("x", 0)]) == nil
      assert Tabs.editor([]) == nil
    end

    test "a claim is one more than the highest" do
      assert Tabs.next_claim([meta("a", 3), meta("b", 0)]) == 4
      assert Tabs.next_claim([]) == 1
    end
  end

  describe "settle/2" do
    test "a tab that edits releases to a tab that claims higher" do
      me = meta("a", 1)
      other = meta("b", 2, 200)

      settled = Tabs.settle(state(me, :editing), [me, other])

      assert settled.mode == :released
      assert settled.actions == [{:release, other.pid}, :unclaim]
      assert settled.meta.claim == 0
      assert settled.other == %{opened_at: 200}
    end

    test "a waiting tab stays waiting while the other edits, and hears when it closed" do
      me = meta("a", 0)
      other = meta("b", 1, 300)

      waiting = Tabs.settle(state(me, :waiting), [me, other])
      assert waiting.mode == :waiting
      assert waiting.actions == []
      assert waiting.other == %{opened_at: 300}
      refute waiting.closed?

      closed = Tabs.settle(waiting, [me])
      assert closed.mode == :waiting
      assert closed.closed?
      assert closed.actions == []
    end

    test "nothing claims by itself when the editing tab closes" do
      me = meta("a", 1)
      editor = meta("b", 2)

      released = Tabs.settle(state(me, :editing), [me, editor])
      assert released.mode == :released

      # Its presence still has the claim it edited with: it is not taken
      # back without the editor asking.
      left = Tabs.settle(released, [me])
      assert left.mode == :released
      assert left.closed?
      assert left.actions == []
    end

    test "a tab that claimed waits for the handover while the other tab is there" do
      me = meta("a", 3)
      from = meta("b", 2)

      taking = Tabs.settle(state(me, :taking, from: from.pid), [me, from])
      assert taking.mode == :taking

      # The other tab closed before it could hand over
      gone = Tabs.settle(taking, [me])
      assert gone.mode == :editing
      assert gone.actions == [:took_over]
    end

    test "a tab that claimed and lost a race goes back to what it was" do
      me = meta("a", 3)
      winner = meta("b", 3)

      lost = Tabs.settle(state(me, :taking, edited?: false), [me, winner])
      assert lost.mode == :waiting
      assert lost.meta.claim == 0
      assert Tabs.settle(state(me, :taking, edited?: true), [me, winner]).mode == :released
    end

    test "the tab's old process, not gone yet after a reconnect, is no other tab, and edits nothing" do
      old = meta("a", 4)
      me = meta("a", 4)

      settled = Tabs.settle(state(me, :editing), [me, old])
      assert settled.mode == :editing
      refute settled.others?

      superseded = Tabs.settle(state(old, :editing), [me, old])
      assert superseded.mode == :released
      assert superseded.actions == [:unclaim]
    end

    test "the tab's own claim counts as it knows it, whatever its presence says" do
      me = meta("a", 4)
      stale = %{me | claim: 0}
      other = meta("b", 2)

      assert Tabs.settle(state(me, :editing), [stale, other]).mode == :editing
    end
  end
end

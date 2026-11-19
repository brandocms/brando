defmodule BrandoAdmin.BlockMoveUndoTest do
  # A block moved (from its menu, or by a drag's `reposition`) shows a
  # "Block moved" notice whose Undo puts it back, as ⌘Z does; ⌘⇧Z moves it
  # again. Another editor's change leaves the history alone, but a move is
  # only taken back while the blocks around it are as it left them: else it
  # is refused with a notice, and nothing moves.
  use Brando.LiveCase

  import Brando.EditSessionEditors, only: [await: 1]

  alias Brando.EditSession

  setup %{conn: conn} = tags do
    c = Brando.ProposalFixtures.context()
    c = Map.merge(c, Brando.ProposalFixtures.multi_context(c))

    # More root blocks after the two, empty projects blocks
    extra =
      for n <- 1..Map.get(tags, :extra_roots, 0)//1,
          do: Brando.ProposalFixtures.root_block!(c, :module, c.projects_module, n + 1).uid

    c |> Map.put(:extra_uids, extra) |> Map.put(:a, open(conn, c.work))
  end

  defp open(conn, page) do
    {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
    await_selector(view, "[data-block-uid]")
    view
  end

  defp move(view, uid, direction) do
    view |> element("#block-#{uid}-dropdown [data-block-move=#{direction}]") |> render_click()
    render(view)
  end

  # ⌘Z and ⌘⇧Z outside a text field run the wrapper's `data-undo` / `data-redo`
  defp undo(view), do: view |> with_target(cid_of(view, "[data-undo]")) |> render_hook("undo_structure", %{})
  defp redo(view), do: view |> with_target(cid_of(view, "[data-redo]")) |> render_hook("redo_structure", %{})

  defp order(html, prefix, uids) do
    ~r/id="#{prefix}-([^"]+)"/
    |> Regex.scan(html)
    |> Enum.map(&List.last/1)
    |> Enum.filter(&(&1 in uids))
  end

  defp roots(view, c), do: view |> render() |> order("base", [c.intro_uid, c.multi_uid | c.extra_uids])
  defp children(view, c), do: view |> render() |> order("child", c.child_uids)

  defp notice?(view), do: has_element?(view, "[data-testid=block-moved]")

  defp delete_block(view, uid) do
    view |> element("#block-#{uid}-dropdown button[phx-click=delete_block]") |> render_click()
    render(view)
  end

  defp session(c), do: EditSession.whereis(EditSession.ref_for(c.work))

  test "a root move's notice undoes it, and redo moves it again", %{a: a} = c do
    move(a, c.multi_uid, "up")
    assert roots(a, c) == [c.multi_uid, c.intro_uid]
    assert notice?(a)

    a |> element("[data-testid=block-moved] .block-bin-undo") |> render_click()
    assert roots(a, c) == [c.intro_uid, c.multi_uid]
    refute notice?(a)

    redo(a)
    assert roots(a, c) == [c.multi_uid, c.intro_uid]
    # A move made again is a move: its notice is up, and undoes it
    assert notice?(a)

    # Nothing more to redo
    redo(a)
    assert roots(a, c) == [c.multi_uid, c.intro_uid]

    undo(a)
    assert roots(a, c) == [c.intro_uid, c.multi_uid]
  end

  test "children's moves undo and redo newest first", %{a: a} = c do
    [alpha, beta, gamma] = c.child_uids

    move(a, gamma, "up")
    move(a, alpha, "down")
    assert children(a, c) == [gamma, alpha, beta]
    assert notice?(a)

    undo(a)
    assert children(a, c) == [alpha, gamma, beta]
    undo(a)
    assert children(a, c) == [alpha, beta, gamma]
    refute notice?(a)

    redo(a)
    assert children(a, c) == [alpha, gamma, beta]
    redo(a)
    assert children(a, c) == [gamma, alpha, beta]
  end

  test "a new move ends what redo can do", %{a: a} = c do
    [alpha, beta, gamma] = c.child_uids

    move(a, gamma, "up")
    undo(a)
    assert children(a, c) == [alpha, beta, gamma]

    move(a, c.multi_uid, "up")
    redo(a)
    assert children(a, c) == [alpha, beta, gamma]
    assert roots(a, c) == [c.multi_uid, c.intro_uid]
  end

  test "the notice goes when dismissed, and ⌘Z still undoes the move", %{a: a} = c do
    move(a, c.multi_uid, "up")
    a |> element("[data-testid=block-moved] .block-bin-dismiss") |> render_click()
    refute notice?(a)

    undo(a)
    assert roots(a, c) == [c.intro_uid, c.multi_uid]
  end

  test "a second click on a move notice's Undo does not undo the change before it", %{a: a} = c do
    [alpha, beta, gamma] = c.child_uids

    delete_block(a, alpha)
    move(a, gamma, "up")
    assert children(a, c) == [gamma, beta]

    [_, at] = Regex.run(~r/data-testid="block-moved".*?phx-value-at="(\d+)"/s, render(a))
    a |> element("[data-testid=block-moved] .block-bin-undo") |> render_click()
    assert children(a, c) == [beta, gamma]

    # The click sent again before the page took the first one in: the move
    # it names is no longer the newest change, so the delete stays
    a |> with_target(cid_of(a, "[data-undo]")) |> render_hook("undo_structure", %{"at" => at})
    assert children(a, c) == [beta, gamma]
    assert has_element?(a, "[data-testid=block-bin]")
  end

  describe "with another editor" do
    setup c do
      other = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
      b = open(log_in_user(Phoenix.ConnTest.build_conn(), other), c.work)
      Brando.endpoint().subscribe("user:#{c.current_user.id}")
      %{b: b}
    end

    test "a change elsewhere leaves the undo", %{a: a, b: b} = c do
      [alpha, beta, gamma] = c.child_uids

      move(a, c.multi_uid, "up")
      await(fn -> roots(b, c) == [c.multi_uid, c.intro_uid] end)

      # B reorders the projects; the root order A left stands
      move(b, gamma, "up")
      await(fn -> children(a, c) == [alpha, gamma, beta] end)

      undo(a)
      assert roots(a, c) == [c.intro_uid, c.multi_uid]
      await(fn -> roots(b, c) == [c.intro_uid, c.multi_uid] end)
      refute_received %Phoenix.Socket.Broadcast{event: "toast"}
    end

    test "a move of theirs among the same blocks refuses the undo, with a notice", %{a: a, b: b} = c do
      [alpha, beta, gamma] = c.child_uids

      move(a, gamma, "up")
      await(fn -> children(b, c) == [alpha, gamma, beta] end)

      # B moves Alpha down, among the blocks A's undo would put back
      move(b, alpha, "down")
      await(fn -> children(a, c) == [gamma, alpha, beta] end)

      undo(a)

      assert_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{payload: "Another editor" <> _}}, 2_000
      assert children(a, c) == [gamma, alpha, beta]
      refute notice?(a)

      # The refused move is gone from the history, and nothing older is undone past it
      undo(a)
      assert children(a, c) == [gamma, alpha, beta]
    end

    test "redo is refused the same way", %{a: a, b: b} = c do
      move(a, c.multi_uid, "up")
      undo(a)
      await(fn -> roots(b, c) == [c.intro_uid, c.multi_uid] end)

      # B moves the block where A's redo would
      move(b, c.multi_uid, "up")
      await(fn -> roots(a, c) == [c.multi_uid, c.intro_uid] end)

      redo(a)
      assert_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{payload: "Another editor" <> _}}, 2_000
      assert roots(a, c) == [c.multi_uid, c.intro_uid]
    end

    # A's redo reaches the session after B's move, which A has not seen yet:
    # the session refuses it, so it does not put B's blocks out of place
    test "a redo the session gets after another editor's move is refused there", %{a: a, b: b} = c do
      [alpha, beta, gamma] = c.child_uids

      move(a, gamma, "up")
      undo(a)
      await(fn -> children(b, c) == [alpha, beta, gamma] end)

      session = session(c)
      :sys.suspend(session)
      move(b, alpha, "down")
      redo(a)
      :sys.resume(session)

      assert_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{payload: "Another editor" <> _}}, 2_000
      await(fn -> children(a, c) == [beta, alpha, gamma] end)
      assert children(b, c) == [beta, alpha, gamma]

      # Both stacks are gone
      undo(a)
      redo(a)
      assert children(a, c) == [beta, alpha, gamma]
    end

    test "a root move's redo the session gets after another editor's move is refused there", %{a: a, b: b} = c do
      move(a, c.multi_uid, "up")
      undo(a)
      await(fn -> roots(b, c) == [c.intro_uid, c.multi_uid] end)

      session = session(c)
      :sys.suspend(session)
      move(b, c.intro_uid, "down")
      redo(a)
      :sys.resume(session)

      assert_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{payload: "Another editor" <> _}}, 2_000
      await(fn -> roots(a, c) == [c.multi_uid, c.intro_uid] end)
      assert roots(b, c) == [c.multi_uid, c.intro_uid]
    end

    @tag extra_roots: 2
    test "a root move is undone when another editor deleted a block away from it", %{a: a, b: b} = c do
      [x, y] = c.extra_uids

      move(a, c.intro_uid, "down")
      await(fn -> roots(b, c) == [c.multi_uid, c.intro_uid, x, y] end)

      delete_block(b, y)
      await(fn -> roots(a, c) == [c.multi_uid, c.intro_uid, x] end)

      undo(a)
      assert roots(a, c) == [c.intro_uid, c.multi_uid, x]
      await(fn -> roots(b, c) == [c.intro_uid, c.multi_uid, x] end)
      refute_received %Phoenix.Socket.Broadcast{event: "toast"}
    end

    @tag extra_roots: 1
    test "a root move is refused when another editor put a block where it would go back", %{a: a, b: b} = c do
      [x] = c.extra_uids

      # A moves Intro to the end; B moves X up, between Multi and Intro's old place
      move(a, c.intro_uid, "down")
      move(a, c.intro_uid, "down")
      await(fn -> roots(b, c) == [c.multi_uid, x, c.intro_uid] end)
      undo(a)
      await(fn -> roots(b, c) == [c.multi_uid, c.intro_uid, x] end)

      move(b, x, "up")
      move(b, x, "up")
      await(fn -> roots(a, c) == [x, c.multi_uid, c.intro_uid] end)

      undo(a)

      assert_receive %Phoenix.Socket.Broadcast{
                       event: "toast",
                       payload: %{payload: "Another editor has changed the blocks here" <> _}
                     },
                     2_000

      assert roots(a, c) == [x, c.multi_uid, c.intro_uid]
    end

    test "⌘Z keeps a deleted block in the bin when it cannot go back", %{a: a, b: b} = c do
      [_alpha, _beta, gamma] = c.child_uids

      delete_block(a, gamma)
      await(fn -> not has_element?(b, "#child-#{gamma}") end)

      delete_block(b, c.multi_uid)
      await(fn -> roots(a, c) == [c.intro_uid] end)

      undo(a)
      assert_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{payload: "Another editor removed" <> _}}, 2_000
      assert has_element?(a, "[data-testid=block-bin]")
    end
  end
end

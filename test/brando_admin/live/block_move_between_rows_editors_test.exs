defmodule BrandoAdmin.BlockMoveBetweenRowsEditorsTest do
  # A multi module's entry moved to another row, seen by another editor of
  # the entry. Synchronous, as OtherEditorsReceiveTest: both editors'
  # Presence lookups outlive an async test's sandbox.
  use Brando.LiveCase

  import Brando.EditSessionEditors, only: [await: 1]

  alias BrandoAdmin.Components.Form.BlockField

  setup do
    c = Brando.ProposalFixtures.context()
    c = Brando.ProposalFixtures.multi_context(c)
    row = Brando.ProposalFixtures.root_block!(c, :module, c.projects_module, 2)
    last = Brando.ProposalFixtures.root_block!(c, :module, c.projects_module, 3)
    other = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})

    Map.merge(c, %{
      row_uid: row.uid,
      last_uid: last.uid,
      other_conn: log_in_user(Phoenix.ConnTest.build_conn(), other)
    })
  end

  defp open(conn, page) do
    {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
    await_selector(view, "[data-block-uid]")
    view
  end

  # The children a row shows, in order.
  defp shown(view, row_uid) do
    html = view |> render() |> Floki.parse_document!() |> Floki.find(children(row_uid)) |> Floki.raw_html()

    ~r/<div[^>]+id="child-([^"]+)"[^>]+data-parent_uid="#{row_uid}"/
    |> Regex.scan(html)
    |> Enum.map(&List.last/1)
  end

  defp children(row_uid), do: ~s(.block-children[data-parent-uid="#{row_uid}"])

  defp drop_on_canvas(view, uid, from_uid, old, to_uid, new) do
    view
    |> with_target(cid_of(view, children(from_uid)))
    |> render_hook("reposition", %{
      "uid" => uid,
      "parent_uid" => from_uid,
      "old" => old,
      "new" => new,
      "from" => %{"parentUid" => from_uid},
      "to" => %{"parentUid" => to_uid}
    })

    render(view)
  end

  # Where a view's block field holds `uid`: its parent in the store.
  defp stored_parent(view, uid) do
    {components, _, _} = :sys.get_state(view.pid).components

    Enum.find_value(components, fn
      {_cid, {BlockField, _id, %{block_ops: ops}, _private, _prints}} -> ops.parents[uid]
      _ -> nil
    end)
  end

  # The other editor's view showed the entry in the row it went to, and in
  # the row it left: only the row it went to was refreshed.
  test "the other editor sees a moved entry in the row it went to, and no longer in the row it left",
       %{conn: conn} = c do
    [alpha, beta, gamma] = c.child_uids
    mover = open(conn, c.work)
    watcher = open(c.other_conn, c.work)

    drop_on_canvas(mover, beta, c.multi_uid, 1, c.row_uid, 0)

    await(fn -> shown(watcher, c.row_uid) == [beta] end)
    await(fn -> shown(watcher, c.multi_uid) == [alpha, gamma] end)
  end

  # Another editor's move is shown a moment after it arrives. An entry this
  # editor drags in that moment, from the row where it still shows, used to
  # be let go only by the row the store had it in, and showed twice.
  test "an entry dragged from a row not yet refreshed leaves that row", %{conn: conn} = c do
    put_test_env(:remote_refresh_ms, 60_000)
    [alpha, beta, gamma] = c.child_uids
    mover = open(conn, c.work)
    stale = open(c.other_conn, c.work)

    drop_on_canvas(mover, beta, c.multi_uid, 1, c.row_uid, 0)
    await(fn -> stored_parent(stale, beta) == c.row_uid end)
    assert shown(stale, c.multi_uid) == [alpha, beta, gamma]

    drop_on_canvas(stale, beta, c.multi_uid, 1, c.last_uid, 0)

    assert shown(stale, c.last_uid) == [beta]
    assert shown(stale, c.multi_uid) == [alpha, gamma]
  end
end

defmodule BrandoAdmin.Components.Form.BlockField.SetFieldTest do
  # `{:set_field, ...}`/`{:set_fields, ...}`: the fields one event changed,
  # last arrival wins per field. Two editors in different fields of one
  # block both keep their changes, in a root (whose diff is cumulative) and
  # in a child (whose diff merges).
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content.Block
  alias Brando.Content.TableRow
  alias Brando.Drafts.Params
  alias BrandoAdmin.Components.Form.BlockField.Ops
  alias Ecto.Changeset

  setup do
    c = Brando.ProposalFixtures.context()
    Brando.ProposalFixtures.multi_context(c)
  end

  defp rows(page) do
    import Ecto.Query

    Brando.Pages.Page.Blocks
    |> where([eb], eb.entry_id == ^page.id)
    |> order_by([eb], eb.sequence)
    |> Brando.Repo.all()
    |> Brando.Repo.preload(
      block: [:vars, :refs, :table_rows, :block_identifiers, children: &Brando.Content.Blocks.preload_child_trees/1]
    )
  end

  defp apply!(state, op) do
    {:ok, state} = Ops.apply_op(state, op)
    state
  end

  # What a keystroke in one input of a block's form produces: the form's
  # params with that input changed, cast the way `validate_block` casts it.
  defp keystroke(%Block{} = block, user, path, value) do
    before = Changeset.change(block)
    params = before |> Params.snapshot() |> put_at(path, value)
    changeset = Block.block_changeset(block, params, user.id)
    {:ok, op} = Ops.field_op(before, changeset, block.uid)
    op
  end

  defp root_keystroke(entry_block, user, path, value) do
    before = Changeset.change(entry_block)
    params = before |> Params.snapshot() |> put_at(path, value)
    changeset = Brando.Pages.Page.Blocks.changeset(entry_block, params, user.id)
    {:ok, op} = Ops.field_op(before, changeset, entry_block.block.uid)
    op
  end

  defp put_at(params, [key], value), do: Map.put(params, key, value)

  defp put_at(params, [key, index | rest], value) when is_list(:erlang.map_get(key, params)) do
    Map.update!(params, key, &List.update_at(&1, String.to_integer(index), fn item -> put_at(item, rest, value) end))
  end

  defp put_at(params, [key | rest], value), do: Map.update!(params, key, &put_at(&1, rest, value))

  defp save(page, entry_blocks, ops, user) do
    by_uid = Map.new(entry_blocks, &{&1.block.uid, &1})

    updated =
      Enum.map(ops.order, fn uid ->
        {:ok, params} = Ops.materialize_root(ops, uid)
        Brando.Pages.Page.Blocks.changeset(by_uid[uid], params, user.id, true)
      end)
      |> Brando.Content.Blocks.reject_deleted(true)
      |> Brando.Content.Blocks.strip_render_artifacts()
      |> Enum.map(&Brando.Utils.set_action/1)

    page
    |> Brando.Repo.preload(:entry_blocks)
    |> Changeset.change()
    |> Changeset.put_assoc(:entry_blocks, updated)
    |> Brando.Repo.update!()
  end

  test "an input names its field by identity, with what an empty diff needs", c do
    [_intro, multi] = rows(c.work)
    alpha = hd(multi.block.children)
    info = Enum.find(alpha.refs, &(&1.name == "info"))

    op = keystroke(alpha, c.user, ["refs", "0", "data", "data", "text"], "<p>Alpha, edited</p>")

    assert {:set_field, uid, path, "<p>Alpha, edited</p>", nil} = op
    assert uid == alpha.uid
    assert [{:at, "refs", {"id", id}, skeleton}, {:map, "data", %{"type" => "text"}}, "data", "text"] = path
    assert id == info.id
    assert length(skeleton) == length(alpha.refs)
  end

  test "two editors in different fields of one child both keep their change", c do
    rows = rows(c.work)
    [_intro, multi] = rows
    alpha = hd(multi.block.children)

    text = keystroke(alpha, c.user, ["refs", "0", "data", "data", "text"], "<p>Text by A</p>")
    size = keystroke(alpha, c.user, ["vars", "0", "value"], "50")

    base = Ops.from_entry_blocks(rows)
    one_way = base |> apply!(text) |> apply!(size)
    other_way = base |> apply!(size) |> apply!(text)
    assert Ops.materialize_root(one_way, multi.block.uid) == Ops.materialize_root(other_way, multi.block.uid)

    save(c.work, rows, one_way, c.user)
    [_intro, multi] = rows(c.work)
    alpha = hd(multi.block.children)

    assert Enum.find(alpha.refs, &(&1.name == "info")).data.data.text == "<p>Text by A</p>"
    assert hd(alpha.vars).value == "50"
    # the other ref and the other children are untouched
    assert Enum.find(alpha.refs, &(&1.name == "clip")).video_id == c.video.id
    assert Enum.map(multi.block.children, &hd(&1.vars).value) == ["50", "100", "50"]
  end

  test "two editors in different fields of one root both keep their change", c do
    [intro | _] = rows = rows(c.work)

    description = root_keystroke(intro, c.user, ["block", "description"], "Intro, described")
    text = root_keystroke(intro, c.user, ["block", "refs", "0", "data", "data", "text"], "<p>Intro, edited</p>")

    ops = rows |> Ops.from_entry_blocks() |> apply!(text) |> apply!(description)
    save(c.work, rows, ops, c.user)

    [intro | _] = rows(c.work)
    assert intro.block.description == "Intro, described"
    assert hd(intro.block.refs).data.data.text == "<p>Intro, edited</p>"
  end

  test "the same field: the last to arrive wins, also back to the saved value", c do
    [intro | _] = rows = rows(c.work)
    path = ["block", "refs", "0", "data", "data", "text"]

    first = root_keystroke(intro, c.user, path, "<p>First</p>")
    second = root_keystroke(intro, c.user, path, "<p>Second</p>")
    # typed back from what the editor showed: the saved value is set too
    shown =
      Brando.Pages.Page.Blocks.changeset(
        intro,
        intro |> Changeset.change() |> Params.snapshot() |> put_at(path, "<p>Second</p>"),
        c.user.id
      )

    back_params = intro |> Changeset.change() |> Params.snapshot() |> put_at(path, "<p>Work intro</p>")
    {:ok, back} = Ops.field_op(shown, Brando.Pages.Page.Blocks.changeset(intro, back_params, c.user.id), intro.block.uid)

    ops = rows |> Ops.from_entry_blocks() |> apply!(first) |> apply!(second)

    assert get_in(ops.diffs, [intro.block.uid, "block", "refs"]) |> hd() |> get_in(["data", "data", "text"]) ==
             "<p>Second</p>"

    ops = apply!(ops, back)
    save(c.work, rows, ops, c.user)
    [intro | _] = rows(c.work)
    assert hd(intro.block.refs).data.data.text == "<p>Work intro</p>"
  end

  test "a change to more than one field sets each of them, and leaves the rest of the block alone", c do
    [intro | _] = rows = rows(c.work)
    before = Changeset.change(intro)

    # one field changed: a field op
    params = before |> Params.snapshot() |> put_at(["block", "description"], "One")
    one = Brando.Pages.Page.Blocks.changeset(intro, params, c.user.id)
    assert {:ok, {:set_field, _, ["block", "description"], "One", nil}} = Ops.field_op(before, one, intro.block.uid)

    # two changed in one event (a widget setting a value beside its own)
    params = put_at(params, ["block", "anchor"], "also")
    two = Brando.Pages.Page.Blocks.changeset(intro, params, c.user.id)
    assert {:ok, {:set_fields, uid, changes, nil}} = Ops.field_op(before, two, intro.block.uid)
    assert uid == intro.block.uid
    assert Enum.sort(changes) == [{["block", "anchor"], "also"}, {["block", "description"], "One"}]

    # #8: another editor's change to the text, applied first, is not undone
    text = root_keystroke(intro, c.user, ["block", "refs", "0", "data", "data", "text"], "<p>By B</p>")
    ops = rows |> Ops.from_entry_blocks() |> apply!(text) |> apply!({:set_fields, uid, changes, nil})
    save(c.work, rows, ops, c.user)

    [intro | _] = rows(c.work)
    assert {intro.block.description, intro.block.anchor} == {"One", "also"}
    assert hd(intro.block.refs).data.data.text == "<p>By B</p>"
  end

  test "nothing changed is no op, and render stamps are not fields", c do
    [intro | _] = rows(c.work)
    before = Changeset.change(intro)
    assert Ops.field_op(before, before, intro.block.uid) == {:ok, nil}

    stamped = Changeset.change(intro, block: Changeset.change(intro.block, rendered_html: "<p>x</p>"))
    assert Ops.field_op(before, stamped, intro.block.uid) == {:ok, nil}
  end

  # #12: a list whose items have no identity was named by index, so an item
  # added or removed elsewhere moved every later change onto its neighbour.
  test "a var's options are one field, and new table rows go by their sync uid", c do
    [_intro, multi] = rows(c.work)
    alpha = hd(multi.block.children)
    before = Changeset.change(alpha)
    [var | _] = alpha.vars
    options = [%{"label" => "Small", "value" => "50"}, %{"label" => "Large", "value" => "100"}]

    params =
      before
      |> Params.snapshot()
      |> put_at(["vars", "0", "options"], options)

    changed = Block.block_changeset(alpha, params, c.user.id)

    assert {:ok, {:set_field, _, [{:at, "vars", {"id", id}, _}, "options"], value, nil}} =
             Ops.field_op(before, changed, alpha.uid)

    assert id == var.id
    assert Enum.map(value, & &1["value"]) == ["50", "100"]

    rows_before = %Block{
      id: 1,
      uid: "t",
      table_rows: [%TableRow{sync_uid: "r1", sequence: 0}, %TableRow{sync_uid: "r2", sequence: 1}]
    }

    rows_after =
      put_in(rows_before.table_rows, [%TableRow{sync_uid: "r1", sequence: 0}, %TableRow{sync_uid: "r2", sequence: 7}])

    assert {:ok, {:set_field, "t", [{:at, "table_rows", {"sync_uid", "r2"}, skeleton}, "sequence"], 7, nil}} =
             Ops.field_op(Changeset.change(rows_before), Changeset.change(rows_after), "t")

    assert skeleton == [%{"sync_uid" => "r1"}, %{"sync_uid" => "r2"}]

    # rows added or moved: the list is one field, sent as what changed in it
    moved = put_in(rows_before.table_rows, Enum.reverse(rows_before.table_rows))

    assert {:ok, {:set_field, "t", ["table_rows"], {:list, [_, _], [_, _]}, nil}} =
             Ops.field_op(Changeset.change(rows_before), Changeset.change(moved), "t")
  end

  # A keystroke that crossed another editor's change to the block carries
  # the browser's old values for what that change touched.
  test "fields set back to what the browser showed before another editor's change are left out", c do
    [intro | _] = rows(c.work)
    shown = Changeset.change(intro)
    path = ["block", "refs", "0", "data", "data", "text"]

    # the other editor's text arrived and replaced the form…
    theirs_params = shown |> Params.snapshot() |> put_at(path, "<p>Theirs</p>")
    theirs = Brando.Pages.Page.Blocks.changeset(intro, theirs_params, c.user.id)

    # …while this editor's keystroke in the description, sent from the old
    # form, still holds the old text
    mine_params = shown |> Params.snapshot() |> put_at(["block", "description"], "Mine")
    mine = Brando.Pages.Page.Blocks.changeset(intro, mine_params, c.user.id)

    assert {:ok, {:set_fields, _, [_, _], nil}} = Ops.field_op(theirs, mine, intro.block.uid)

    assert {:ok, {:set_field, _, ["block", "description"], "Mine", nil}} =
             Ops.field_op(theirs, mine, intro.block.uid, {shown, theirs})
  end

  # Round 3 #1: every field set back to its value before the replace was
  # dropped, not only the ones the other editor's change touched. While
  # someone types in the same block the form is replaced every moment, so a
  # backspace, or a toggle set back, was lost.
  test "a field the other editor did not touch counts when set back, a backspace or a toggle", c do
    [intro | _] = rows(c.work)
    text = ["block", "refs", "0", "data", "data", "text"]
    cs = fn params -> Brando.Pages.Page.Blocks.changeset(intro, params, c.user.id) end
    snapshot = intro |> Changeset.change() |> Params.snapshot()

    # A had "abc" in the description; B's text replaced the form
    stale = cs.(put_at(snapshot, ["block", "description"], "abc"))
    replacing = cs.(snapshot |> put_at(["block", "description"], "abc") |> put_at(text, "<p>B typing</p>"))

    # A types "d", then backspaces
    typed = cs.(snapshot |> put_at(["block", "description"], "abcd") |> put_at(text, "<p>B typing</p>"))
    back = cs.(snapshot |> put_at(["block", "description"], "abc") |> put_at(text, "<p>B typing</p>"))

    assert {:ok, {:set_field, _, ["block", "description"], "abc", nil}} =
             Ops.field_op(typed, back, intro.block.uid, {stale, replacing})

    # a toggle set back
    off =
      cs.(
        snapshot
        |> put_at(["block", "description"], "abc")
        |> put_at(text, "<p>B typing</p>")
        |> put_at(["block", "active"], false)
      )

    assert {:ok, {:set_field, _, ["block", "active"], true, nil}} =
             Ops.field_op(off, back, intro.block.uid, {stale, replacing})

    # the field B's change touched, sent back as it was before: an echo
    echo = cs.(snapshot |> put_at(["block", "description"], "abcd"))

    assert {:ok, {:set_field, _, ["block", "description"], "abcd", nil}} =
             Ops.field_op(replacing, echo, intro.block.uid, {stale, replacing})
  end

  # Round 3 #5: a list that gained, lost or reordered items was set whole,
  # so of two editors each adding an item, one lost theirs.
  test "two editors adding and removing list items both keep their change", c do
    [_intro, multi] = rows = rows(c.work)
    [alpha, beta | _] = multi.block.children
    base = Ops.from_entry_blocks(rows)

    list_op = fn block, change ->
      before = Changeset.change(block)
      snapshot = Params.snapshot(before)
      changed = Block.block_changeset(block, Map.update!(snapshot, "refs", change), c.user.id)
      {:ok, op} = Ops.field_op(before, changed, block.uid)
      op
    end

    new_ref = fn name ->
      %{
        "uid" => Brando.Utils.generate_uid(),
        "name" => name,
        "data" => %{"type" => "text", "data" => %{"text" => "<p>#{name}</p>"}}
      }
    end

    # A adds a ref to alpha, B adds another; A drops beta's clip, B edits its info
    a_adds = list_op.(alpha, &(&1 ++ [new_ref.("by_a")]))
    b_adds = list_op.(alpha, &(&1 ++ [new_ref.("by_b")]))
    a_drops = list_op.(beta, &Enum.reject(&1, fn ref -> ref["name"] == "clip" end))
    assert {:set_field, _, ["refs"], {:list, _, _}, _} = a_adds

    b_edits = keystroke(beta, c.user, ["refs", "0", "data", "data", "text"], "<p>Beta, by B</p>")

    one_way = Enum.reduce([a_adds, b_adds, a_drops, b_edits], base, &apply!(&2, &1))
    other_way = Enum.reduce([b_adds, b_edits, a_adds, a_drops], base, &apply!(&2, &1))

    # in either order, the same items (their order follows who came last)
    names = fn state ->
      {:ok, %{"block" => %{"children" => [alpha, beta | _]}}} = Ops.materialize_root(state, multi.block.uid)
      {alpha["refs"] |> Enum.map(&(&1["name"] || &1["id"])) |> Enum.sort(), length(beta["refs"])}
    end

    assert names.(one_way) == names.(other_way)

    save(c.work, rows, one_way, c.user)
    [_intro, multi] = rows(c.work)
    [alpha, beta | _] = multi.block.children
    assert alpha.refs |> Enum.map(& &1.name) |> Enum.sort() == ~w(by_a by_b clip info)
    assert Enum.map(beta.refs, & &1.name) == ["info"]
    assert hd(beta.refs).data.data.text == "<p>Beta, by B</p>"
  end

  # #1: a field op made while a block was new names its rows by uid. Replayed
  # after a save gave them ids, and followed by an op that names them by id,
  # both must land on the one row — two items for it saved a new, nameless
  # ref.
  test "an op that names a row by uid and one that names it by id meet on the same row", c do
    [intro | _] = rows = rows(c.work)
    ref = hd(intro.block.refs)
    by_id = root_keystroke(intro, c.user, ["block", "refs", "0", "data", "data", "text"], "<p>By id</p>")

    {:set_field, uid, [block, {:at, "refs", {"id", _}, skeleton} | rest], _, _} = by_id

    by_uid_skeleton =
      Enum.map(skeleton, fn %{"id" => id} -> %{"uid" => Enum.find(intro.block.refs, &(&1.id == id)).uid} end)

    by_uid = {:set_field, uid, [block, {:at, "refs", {"uid", ref.uid}, by_uid_skeleton} | rest], "<p>By uid</p>", nil}

    base = Ops.from_entry_blocks(rows)

    for ops <- [[by_uid, by_id], [by_id, by_uid]] do
      state = Enum.reduce(ops, base, &apply!(&2, &1))
      assert [_one] = get_in(state.diffs, [uid, "block", "refs"])
    end

    state = base |> apply!(by_uid) |> apply!(by_id)
    save(c.work, rows, state, c.user)
    [intro | _] = rows(c.work)
    assert [%{data: %{data: %{text: "<p>By id</p>"}}}] = intro.block.refs
  end
end

defmodule BrandoAdmin.Components.Form.BlockField.SetFieldTest do
  # `{:set_field, ...}`: one field of one block, last arrival wins. Two
  # editors in different fields of one block both keep their changes, in a
  # root (whose diff is cumulative) and in a child (whose diff merges).
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content.Block
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
    params = block |> Changeset.change() |> Params.snapshot() |> put_at(path, value)
    changeset = Block.block_changeset(block, params, user.id)
    {:ok, op} = Ops.field_op(changeset, block.uid, ["child_block" | path])
    op
  end

  defp root_keystroke(entry_block, user, path, value) do
    params = entry_block |> Changeset.change() |> Params.snapshot() |> put_at(path, value)
    changeset = Brando.Pages.Page.Blocks.changeset(entry_block, params, user.id)
    {:ok, op} = Ops.field_op(changeset, entry_block.block.uid, ["entry_block" | path])
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
    back = root_keystroke(intro, c.user, path, "<p>Work intro</p>")

    ops = rows |> Ops.from_entry_blocks() |> apply!(first) |> apply!(second)

    assert get_in(ops.diffs, [intro.block.uid, "block", "refs"]) |> hd() |> get_in(["data", "data", "text"]) ==
             "<p>Second</p>"

    ops = apply!(ops, back)
    save(c.work, rows, ops, c.user)
    [intro | _] = rows(c.work)
    assert hd(intro.block.refs).data.data.text == "<p>Work intro</p>"
  end

  test "a change to more than the input it names goes as the whole block", c do
    [intro | _] = rows(c.work)
    before = Changeset.change(intro)

    # one field changed: a field op
    params = before |> Params.snapshot() |> put_at(["block", "description"], "One")
    one = Brando.Pages.Page.Blocks.changeset(intro, params, c.user.id)

    assert {:ok, {:set_field, _, _, "One", _}} =
             Ops.field_op(one, intro.block.uid, ["entry_block", "block", "description"], before)

    # the event names one field but two changed (a widget setting a value
    # beside its own, rows moved by dragging): not a field op
    params = put_at(params, ["block", "anchor"], "also")
    two = Brando.Pages.Page.Blocks.changeset(intro, params, c.user.id)
    assert Ops.field_op(two, intro.block.uid, ["entry_block", "block", "description"], before) == :error
  end

  test "a hidden helper input is not a field", c do
    [intro | _] = rows(c.work)
    changeset = Changeset.change(intro)
    assert Ops.field_op(changeset, intro.block.uid, ["entry_block", "block", "refs", "0", "_persistent_id"]) == :error
    assert Ops.field_op(changeset, intro.block.uid, ["entry_block", "block", "rendered_html"]) == :error
  end
end

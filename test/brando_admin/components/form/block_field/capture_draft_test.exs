defmodule BrandoAdmin.Components.Form.BlockField.CaptureDraftTest do
  # A recovery capture used to rebuild every root twice, ~80 ms of the
  # LiveView process at 115 roots, every few seconds while someone edits.
  # Roots whose inputs did not change since the last capture now reuse its
  # result; anything that did change is rebuilt exactly as before.
  use ExUnit.Case, async: true

  alias Brando.Content.Block
  alias BrandoAdmin.Components.Form.BlockField
  alias BrandoAdmin.Components.Form.BlockField.Ops
  alias Phoenix.Component
  alias Phoenix.LiveComponent.CID

  @block_module Brando.Pages.Page.Blocks
  @user %{id: 1}
  @reply_to %CID{cid: 1}

  defp row(uid, id, sequence) do
    block =
      struct(Block, %{
        id: id,
        uid: uid,
        type: :module,
        active: true,
        collapsed: false,
        sequence: sequence,
        module_id: 5,
        creator_id: 1,
        source: @block_module,
        vars: [],
        refs: [],
        table_rows: [],
        children: [],
        block_identifiers: []
      })

    %@block_module{id: id + 1000, entry_id: 1, block_id: id, sequence: sequence, block: block}
  end

  defp socket(rows) do
    Component.assign(%Phoenix.LiveView.Socket{}, %{
      block_module: @block_module,
      block_field: "blocks",
      current_user: @user,
      entry_blocks: rows,
      block_ops: Ops.from_entry_blocks(rows)
    })
  end

  defp capture(socket, forms \\ %{}) do
    {:ok, socket} =
      BlockField.update(%{event: "capture_draft", capture_id: "c", reply_to: @reply_to, forms: forms}, socket)

    assert_received {:phoenix, :send_update, {@reply_to, %{event: "draft_part", data: roots}}}
    {Map.new(roots, &{&1["block"]["uid"], &1}), socket}
  end

  defp apply!(socket, op) do
    {:ok, ops} = Ops.apply_op(socket.assigns.block_ops, op)
    Component.assign(socket, :block_ops, ops)
  end

  test "unchanged roots reuse the previous capture; changed ones are rebuilt" do
    {first, socket} = capture(socket([row("a", 1, 0), row("b", 2, 1), row("c", 3, 2)]))

    {second, socket} = capture(socket)
    for uid <- ~w(a b c), do: assert(:erts_debug.same(first[uid], second[uid]))

    socket = apply!(socket, {:update, "b", %{"block" => %{"description" => "Edited"}}})
    {third, socket} = capture(socket)
    assert third["b"]["block"]["description"] == "Edited"
    assert :erts_debug.same(second["a"], third["a"])
    assert :erts_debug.same(second["c"], third["c"])

    # A browser value overlaid on a root rebuilds that root, and only it.
    {fourth, _socket} = capture(socket, %{"c" => %{"block" => %{"description" => "Typed"}}})
    assert fourth["c"]["block"]["description"] == "Typed"
    assert :erts_debug.same(third["a"], fourth["a"])
    assert :erts_debug.same(third["b"], fourth["b"])
  end

  test "a reused root equals what a fresh capture builds" do
    rows = [row("a", 1, 0), row("b", 2, 1)]
    {_, socket} = capture(socket(rows))
    socket = apply!(socket, {:update, "a", %{"block" => %{"description" => "Edited"}}})
    {cached, _} = capture(socket)

    {fresh, _} = capture(Component.assign(socket, :draft_snapshots, %{}))
    assert cached == fresh
  end
end

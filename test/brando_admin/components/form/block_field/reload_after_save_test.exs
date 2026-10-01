defmodule BrandoAdmin.Components.Form.BlockField.ReloadAfterSaveTest do
  # After a save, every mounted root used to be re-seeded with a fresh form
  # from the reloaded rows: ~8 KB and one frame per root, 1.1 MB at 115 roots.
  # A save that persisted what the editor showed leaves untouched roots
  # exactly as they were, so those are skipped — but only when that is
  # proven, because the point of the re-seed is that the editor holds the
  # saved entry and nothing else.
  use ExUnit.Case, async: true

  alias Brando.Content.Block
  alias Brando.Content.Var
  alias BrandoAdmin.Components.Form.BlockField
  alias BrandoAdmin.Components.Form.BlockField.Ops
  alias Phoenix.Component

  @block_module Brando.Pages.Page.Blocks
  @user %{id: 1}

  defp block(uid, id, sequence, attrs) do
    struct(
      Block,
      Map.merge(
        %{
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
        },
        attrs
      )
    )
  end

  defp row(uid, id, sequence, attrs \\ %{}) do
    %@block_module{id: id + 1000, entry_id: 1, block_id: id, sequence: sequence, block: block(uid, id, sequence, attrs)}
  end

  defp var(id, value),
    do: %Var{id: id, key: "title", type: :string, label: "Title", value: value, placement: :content, width: :full}

  # `seeded` is what the roots were mounted from, `saved` what the save wrote.
  defp reload(seeded, saved, ops, scope \\ :changed) do
    seed_forms = Map.new(seeded, &{&1.block.uid, BlockField.to_change_form(@block_module, &1, %{}, @user.id)})

    socket =
      %Phoenix.LiveView.Socket{}
      |> Component.assign(:block_module, @block_module)
      |> Component.assign(:current_user, @user)
      |> Component.assign(:entry_blocks, saved)
      |> Component.assign(:seed_forms, seed_forms)
      |> Component.assign(:block_ops, ops)

    {:ok, socket} = BlockField.update(%{event: "reload_all_blocks", scope: scope}, socket)
    {reseeded(), socket}
  end

  defp reseeded(acc \\ []) do
    receive do
      {:phoenix, :send_update, {{_, "block-" <> uid}, %{event: "replace_form"}}} -> reseeded([uid | acc])
    after
      0 -> Enum.sort(acc)
    end
  end

  defp apply!(ops, op) do
    {:ok, ops} = Ops.apply_op(ops, op)
    ops
  end

  test "roots the save left untouched keep their forms" do
    rows = [row("a", 1, 0), row("b", 2, 1, %{vars: [var(20, "Hello")]})]

    assert {[], socket} = reload(rows, rows, Ops.from_entry_blocks(rows))
    assert socket.assigns.block_ops == Ops.from_entry_blocks(rows)
    assert Map.keys(socket.assigns.seed_forms) == ["a", "b"]
  end

  test "an edited root is re-seeded even when the save wrote its values verbatim" do
    seeded = [row("a", 1, 0), row("b", 2, 1)]
    saved = [row("a", 1, 0), row("b", 2, 1, %{description: "New"})]

    ops =
      seeded
      |> Ops.from_entry_blocks()
      |> apply!({:update, "b", %{"block" => %{"description" => "New"}}})

    assert {["b"], _} = reload(seeded, saved, ops)
  end

  test "a root whose saved row differs from what the editor holds is re-seeded" do
    seeded = [row("a", 1, 0, %{vars: [var(20, "Hello")]})]
    # Nothing in the store says it changed, so the editor shows "Hello": the
    # re-seed is what makes a save that wrote something else visible.
    saved = [row("a", 1, 0, %{vars: [var(20, "Changed elsewhere")]})]

    assert {["a"], _} = reload(seeded, saved, Ops.from_entry_blocks(seeded))
  end

  test "reordered roots are re-seeded, untouched neighbours are not" do
    seeded = [row("a", 1, 0), row("b", 2, 1), row("c", 3, 2)]
    saved = [row("b", 2, 0), row("a", 1, 1), row("c", 3, 2)]
    ops = seeded |> Ops.from_entry_blocks() |> apply!({:reorder, ["b", "a", "c"]})

    assert {["a", "b"], _} = reload(seeded, saved, ops)
  end

  test "a root inserted before the save is re-seeded with its new ids" do
    seeded = [row("a", 1, 0)]
    saved = [row("a", 1, 0), row("n", 9, 1)]

    ops =
      seeded
      |> Ops.from_entry_blocks()
      |> apply!({:insert, "n", :end, %{"block" => %{"uid" => "n", "type" => "module"}}})

    assert {["n"], _} = reload(seeded, saved, ops)
  end

  test "a root whose child was edited is re-seeded" do
    child = block("c1", 11, 0, %{parent_id: 1, vars: [var(21, "Child")]})
    seeded = [row("a", 1, 0, %{children: [child]})]
    saved = [row("a", 1, 0, %{children: [%{child | description: "Edited"}]})]

    ops =
      seeded
      |> Ops.from_entry_blocks()
      |> apply!({:update, "c1", %{"description" => "Edited"}})

    assert {["a"], _} = reload(seeded, saved, ops)
  end

  test "other reloads re-seed every root" do
    rows = [row("a", 1, 0), row("b", 2, 1)]

    assert {["a", "b"], _} = reload(rows, rows, Ops.from_entry_blocks(rows), :all)
  end
end

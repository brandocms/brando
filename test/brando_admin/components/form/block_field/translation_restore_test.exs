defmodule BrandoAdmin.Components.Form.BlockField.TranslationRestoreTest do
  # A synchronized translation's pending version reaching a block field that
  # has no edit session, in a tab that does not edit
  # (`LiveView.Form.Tabs`): the field changes nothing, so its roots stay in
  # the order it shows them, and each still has a form to be drawn with
  # (`root_shells/2` fetches one per root).
  use ExUnit.Case, async: true

  alias Brando.Content.Block
  alias BrandoAdmin.Components.Form.BlockField
  alias BrandoAdmin.Components.Form.BlockField.Ops
  alias Phoenix.Component

  @block_module Brando.Pages.Page.Blocks
  @user %{id: 1}

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

  defp changeset(row), do: BlockField.to_change_form(@block_module, row, %{}, @user.id).source

  test "a root the version drops keeps its form in a tab that does not edit" do
    rows = [row("kept", 1, 0), row("dropped", 2, 1)]
    ops = Ops.from_entry_blocks(rows)

    socket =
      %Phoenix.LiveView.Socket{}
      |> Component.assign(:block_field, :blocks)
      |> Component.assign(:block_module, @block_module)
      |> Component.assign(:current_user, @user)
      |> Component.assign(:entry_blocks, rows)
      |> Component.assign(
        :seed_forms,
        Map.new(rows, &{&1.block.uid, BlockField.to_change_form(@block_module, &1, %{}, 1)})
      )
      |> Component.assign(:block_ops, ops)
      |> Component.assign(:root_order, ops.order)
      |> Component.assign(:edit_session, :failed)
      |> Component.assign(:tab_editing?, false)

    # The version leaves the second row out (`put_assoc/3` marks it `:replace`).
    [kept, dropped] = Enum.map(rows, &changeset/1)
    changesets = [kept, %{dropped | action: :replace}]

    {:ok, socket} =
      BlockField.update(
        %{event: "restore_draft", source: :translation, changesets: changesets, entry_blocks: rows},
        socket
      )

    %{root_order: root_order, seed_forms: seed_forms} = socket.assigns
    assert root_order == ["kept", "dropped"]
    assert Enum.all?(root_order, &Map.has_key?(seed_forms, &1))
  end
end

defmodule BrandoAdmin.Components.Form.Block.PreviewTest do
  use ExUnit.Case, async: true

  alias Brando.Content.Block, as: ContentBlock
  alias BrandoAdmin.Components.Form.Block
  alias Ecto.Changeset

  defp wrap(block, :root) do
    %Brando.Pages.Page.Blocks{}
    |> Changeset.change()
    |> Changeset.put_assoc(:block, block)
  end

  defp wrap(block, _), do: Changeset.change(block)

  test "entry delivery updates editor splits without stamping a discarded block render" do
    socket =
      Phoenix.Component.assign(%Phoenix.LiveView.Socket{}, %{
        entry: %{title: "Before"},
        liquid_splits: [],
        form: :unchanged,
        live_preview_active?: true,
        belongs_to: :root
      })

    assert {:ok, updated} =
             Block.update(%{event: "update_entry_field", path: [Access.key(:title)], change: "After"}, socket)

    assert updated.assigns.entry.title == "After"
    assert updated.assigns.form == :unchanged

    # A list change (a row added to a subform) arrives as the field's rows
    assert {:ok, listed} =
             Block.update(%{event: "update_entry_field", path: [Access.key(:items)], change: [%{key: "a"}]}, updated)

    assert listed.assigns.entry.items == [%{key: "a"}]

    assert {:ok, replaced} = Block.update(%{event: "replace_entry", entry: %{title: "Replaced"}}, updated)
    assert replaced.assigns.entry.title == "Replaced"
    assert replaced.assigns.form == :unchanged
  end

  for belongs_to <- [:root, :container, :slot] do
    test "reactivation includes owned children (#{belongs_to})" do
      belongs_to = unquote(belongs_to)
      slot = %ContentBlock{uid: "region", type: :slot, children: []}

      for attrs <- [
            %{type: :container, children: []},
            %{type: :module, multi: true, children: []},
            %{type: :module, multi: false, children: [slot]},
            %{type: :slot, children: []}
          ] do
        block = struct(ContentBlock, Map.put(attrs, :uid, "owner"))
        inactive = wrap(%{block | active: false}, belongs_to)
        active = wrap(%{block | active: true}, belongs_to)

        assert Block.should_force_live_preview_update?(inactive, active, belongs_to)
        refute Block.should_force_live_preview_update?(active, active, belongs_to)
        refute Block.should_force_live_preview_update?(active, inactive, belongs_to)
      end
    end
  end

  test "leaf modules need no child render, including when children are not preloaded" do
    persisted = Ecto.put_meta(%ContentBlock{id: 123, uid: "persisted-leaf"}, state: :loaded)

    for block <- [%ContentBlock{uid: "leaf"}, %ContentBlock{uid: "leaf", children: []}, persisted] do
      inactive = Changeset.change(%{block | active: false})
      active = Changeset.change(block)
      refute Block.should_force_live_preview_update?(inactive, active, :container)
    end
  end

  test "slot owners request a full preview from the operation store" do
    for attrs <- [
          %{type: :module, multi: false, has_children?: true, belongs_to: :root},
          %{type: :module, multi: false, has_children?: true, belongs_to: :container},
          %{type: :slot, belongs_to: :root},
          %{type: :module, belongs_to: :slot}
        ] do
      socket =
        %Phoenix.LiveView.Socket{}
        |> Phoenix.Component.assign(Map.merge(attrs, %{live_preview_active?: true, form_id: "page"}))

      Block.maybe_update_live_preview_block(socket)
      refute Block.render_live_preview_block?(socket)

      assert_receive {:phoenix, :send_update,
                      {{BrandoAdmin.Components.Form, "page"}, %{id: "page", event: "update_live_preview"}}}
    end
  end
end

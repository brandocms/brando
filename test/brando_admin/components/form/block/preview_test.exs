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

      assert_receive {:phoenix, :send_update,
                      {{BrandoAdmin.Components.Form, "page"}, %{id: "page", event: "update_live_preview"}}}
    end
  end
end

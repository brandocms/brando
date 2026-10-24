defmodule BrandoAdmin.Components.Form.TransformerPickedVideoTest do
  # A transformer opens the video picker for an entry. A video added there from
  # a URL or a provider's library is handed over as `video_created_from_url`,
  # which the transformer had no clause for: its general `update/2` took the
  # message as assigns and the entry kept its old video.
  use Brando.ConnCase

  alias Brando.Factory
  alias BrandoAdmin.Components.Form.Transformer
  alias Phoenix.Component

  test "a video added from a URL in the picker is set on the entry it was picked for" do
    video = Factory.insert(:video)
    socket = socket(["item-1"], "item-1")

    {:ok, socket} =
      Transformer.update(%{event: "video_created_from_url", video_data: %{id: video.id}, video_changeset: nil}, socket)

    [item] = socket.assigns.items
    assert item.changes.clip_id == video.id
    assert item.assets.clip.id == video.id
    assert socket.assigns.picking_dom_id == nil
    refute Map.has_key?(socket.assigns, :video_data)
  end

  # The editor may close the picker and open it for another entry while an
  # upload started for the first one transfers.
  test "a video uploaded in the picker goes to the entry it was uploaded for" do
    video = Factory.insert(:video)
    socket = socket(["item-1", "item-2"], "item-2")

    {:ok, socket} =
      Transformer.update(
        %{event: "select_video", id: video.id, expected_asset_id: "none", pick_context: "item-1"},
        socket
      )

    [first, second] = socket.assigns.items
    assert first.changes.clip_id == video.id
    refute Map.get(second.changes, :clip_id)
    # Still picking for the second
    assert socket.assigns.picking_dom_id == "item-2"
  end

  test "a video uploaded in the picker leaves an entry that shows another video by then" do
    video = Factory.insert(:video)
    picked = Factory.insert(:video)
    socket = socket(["item-1"], nil)
    socket = Component.assign(socket, :items, [Transformer.new_item("item-1", %{title: "Row", clip_id: picked.id})])

    {:ok, socket} =
      Transformer.update(
        %{event: "select_video", id: video.id, expected_asset_id: "none", pick_context: "item-1"},
        socket
      )

    [item] = socket.assigns.items
    refute Map.get(item.changes, :clip_id) == video.id
  end

  defp socket(dom_ids, picking_dom_id) do
    %Phoenix.LiveView.Socket{private: %{lifecycle: %Phoenix.LiveView.Lifecycle{}, live_temp: %{}}}
    |> Component.assign(:items, Enum.map(dom_ids, &Transformer.new_item(&1, %{title: "Row", clip_id: nil})))
    |> Component.assign(:form_id, nil)
    |> Component.assign(:relation_key, :items)
    |> Component.assign(:video_field, :clip)
    |> Component.assign(:subform, %Brando.Blueprint.Forms.Subform{})
    |> Component.assign(:picking_dom_id, picking_dom_id)
    |> Component.assign(:initialized?, true)
    |> Phoenix.LiveView.stream(:transformer_items, [])
  end
end

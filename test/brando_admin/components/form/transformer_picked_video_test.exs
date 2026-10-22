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

    socket =
      %Phoenix.LiveView.Socket{private: %{lifecycle: %Phoenix.LiveView.Lifecycle{}, live_temp: %{}}}
      |> Component.assign(:items, [Transformer.new_item("item-1", %{title: "Row", clip_id: nil})])
      |> Component.assign(:form_id, nil)
      |> Component.assign(:relation_key, :items)
      |> Component.assign(:video_field, :clip)
      |> Component.assign(:subform, %Brando.Blueprint.Forms.Subform{})
      |> Component.assign(:picking_dom_id, "item-1")
      |> Component.assign(:initialized?, true)
      |> Phoenix.LiveView.stream(:transformer_items, [])

    {:ok, socket} =
      Transformer.update(%{event: "video_created_from_url", video_data: %{id: video.id}, video_changeset: nil}, socket)

    [item] = socket.assigns.items
    assert item.changes.clip_id == video.id
    assert item.assets.clip.id == video.id
    assert socket.assigns.picking_dom_id == nil
    refute Map.has_key?(socket.assigns, :video_data)
  end
end

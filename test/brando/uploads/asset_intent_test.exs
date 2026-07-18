defmodule Brando.Uploads.AssetIntentTest do
  use ExUnit.Case, async: true

  alias Brando.Uploads.AssetIntent

  @topic "form:83f75a86-7f34-4317-8b7d-671a66253d4d"

  test "normalizes a nested entry gallery target without losing its wire shape" do
    assert {:ok, target} =
             AssetIntent.normalize(%{
               "kind" => "entry_field_gallery",
               "component_id" => "project_clients_0_gallery",
               "field" => "project_gallery",
               "path" => [Atom.to_string(:clients), 0],
               "asset_type" => "image",
               "config_target" => {"gallery", Brando.Pages.Page, :project_gallery},
               "deliver_topic" => @topic
             })

    assert target["path"] == ["clients", 0]
    assert target["config_target"] == "gallery:Brando.Pages.Page:project_gallery"
    assert target["deliver_topic"] == @topic
  end

  test "rejects mismatched asset and destination types" do
    assert {:error, "Asset type is not valid" <> _} =
             AssetIntent.normalize(%{
               kind: "block_ref_picture",
               component_id: "picture-1",
               asset_type: "video",
               deliver_topic: @topic
             })
  end

  test "rejects arbitrary PubSub topics and unknown paths" do
    base = %{
      kind: "entry_field",
      field: "title",
      asset_type: "image",
      deliver_topic: @topic
    }

    assert {:error, "Invalid upload delivery topic"} =
             AssetIntent.normalize(%{base | deliver_topic: "admin:users"})

    assert {:error, "Unknown upload path segment"} =
             AssetIntent.normalize(Map.put(base, :path, ["definitely_not_an_existing_field_atom_xyz"]))
  end

  test "requires adapter identity for vars and refs" do
    assert {:error, "Missing component id"} =
             AssetIntent.normalize(%{
               kind: "block_var",
               var_key: "cover",
               asset_type: "image",
               deliver_topic: @topic
             })

    assert {:error, "Missing var key"} =
             AssetIntent.normalize(%{
               kind: "block_var",
               component_id: "var-1",
               asset_type: "image",
               deliver_topic: @topic
             })
  end

  test "accepts video-only picker and transformer delivery targets" do
    for kind <- ["video_picker", "transformer_video"] do
      assert {:ok, target} =
               AssetIntent.normalize(%{
                 kind: kind,
                 component_id: "video-target",
                 asset_type: "video",
                 config_target: "default",
                 deliver_topic: @topic
               })

      assert target["kind"] == kind

      assert {:error, "Asset type is not valid" <> _} =
               AssetIntent.normalize(%{
                 kind: kind,
                 component_id: "video-target",
                 asset_type: "image",
                 deliver_topic: @topic
               })
    end
  end
end

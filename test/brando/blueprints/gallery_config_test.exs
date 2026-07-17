defmodule Brando.GalleryConfigTest.Schema do
  use Brando.Blueprint,
    application: "Brando",
    domain: "GalleryConfigTest",
    schema: "Schema",
    singular: "gallery_config_test_schema",
    plural: "gallery_config_test_schemas",
    gettext_module: Brando.Gettext

  identifier false
  persist_identifier false

  assets do
    asset :media, :gallery,
      cfg: %{
        image: %{upload_path: "images/gallery-test", size_limit: 12_000_000},
        video: %{upload_path: "videos/gallery-test", size_limit: 345_000_000, upload_strategy: :local}
      }
  end
end

defmodule Brando.Blueprints.GalleryConfigTest do
  use ExUnit.Case, async: true

  alias Brando.GalleryConfigTest.Schema

  test "gallery blueprint config retains distinct image and video configs" do
    %{cfg: cfg} = Brando.Blueprint.Assets.__asset_opts__(Schema, :media)

    assert %Brando.Type.ImageConfig{upload_path: "images/gallery-test", size_limit: 12_000_000} = cfg.image

    assert %Brando.Type.VideoConfig{
             upload_path: "videos/gallery-test",
             size_limit: 345_000_000,
             upload_strategy: :local
           } = cfg.video
  end

  test "gallery assets generate a deleting gallery association" do
    assert %{related: Brando.Galleries.Gallery, on_replace: :delete} =
             Schema.__schema__(:association, :media)
  end

  test "image and video upload resolvers select their side of a gallery config" do
    target = "gallery:Elixir.Brando.GalleryConfigTest.Schema:media"

    assert {:ok, %Brando.Type.ImageConfig{upload_path: "images/gallery-test"}} =
             Brando.Images.get_config_for(target)

    assert {:ok, %Brando.Type.VideoConfig{upload_path: "videos/gallery-test"}} =
             Brando.Videos.get_config_for(target)

    assert {%Brando.Type.ImageConfig{size_limit: 12_000_000}, ^target} =
             Brando.Uploads.resolve_image_config(target)

    assert {%Brando.Type.VideoConfig{size_limit: 345_000_000}, ^target} =
             Brando.Uploads.resolve_video_config(target)
  end

  test "legacy flat gallery config remains an image override" do
    asset = %Brando.Blueprint.Assets.Asset{
      name: :legacy_gallery,
      type: :gallery,
      opts: [cfg: %{upload_path: "images/legacy-gallery"}]
    }

    assert {:ok, %{opts: %{cfg: cfg}}} = Brando.Blueprint.Assets.Dsl.transform(asset)
    assert %Brando.Type.ImageConfig{upload_path: "images/legacy-gallery"} = cfg.image
    assert %Brando.Type.VideoConfig{} = cfg.video
  end

  test "legacy ImageConfig structs remain valid flat gallery configs" do
    asset = %Brando.Blueprint.Assets.Asset{
      name: :legacy_struct_gallery,
      type: :gallery,
      opts: [cfg: %Brando.Type.ImageConfig{upload_path: "images/legacy-struct"}]
    }

    assert {:ok, %{opts: %{cfg: cfg}}} = Brando.Blueprint.Assets.Dsl.transform(asset)
    assert %Brando.Type.ImageConfig{upload_path: "images/legacy-struct"} = cfg.image
    assert %Brando.Type.VideoConfig{} = cfg.video
  end
end

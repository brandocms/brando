defmodule Brando.Blueprint.AssetConfigTest do
  use ExUnit.Case, async: true

  alias Brando.Blueprint.Assets

  defmodule ConfiguredAssets do
    use Brando.Blueprint,
      application: "Brando",
      domain: "AssetConfigTest",
      schema: "ConfiguredAssets",
      singular: "configured_asset",
      plural: "configured_assets",
      gettext_module: Brando.Gettext

    assets do
      asset :default_image, :image, cfg: :default
      asset :dynamic_image, :image, cfg: fn -> %{upload_path: "images/dynamic"} end
      asset :database_image, :image, cfg: :db
      asset :default_video, :video, cfg: :default
      asset :default_file, :file, cfg: :default
      asset :target_file, :file, cfg: :config_target
    end
  end

  test "all materialized asset configs are typed and merged with defaults" do
    assets = Map.new(Assets.__assets__(ConfiguredAssets), &{&1.name, &1})

    assert %Brando.Type.ImageConfig{} = assets.default_image.opts.cfg
    assert %Brando.Type.ImageConfig{upload_path: "images/dynamic"} = assets.dynamic_image.opts.cfg
    assert %Brando.Type.VideoConfig{} = assets.default_video.opts.cfg
    assert %Brando.Type.FileConfig{} = assets.default_file.opts.cfg
  end

  test "deferred configs retain their association module metadata" do
    assets = Map.new(Assets.__assets__(ConfiguredAssets), &{&1.name, &1})

    assert %{cfg: :db, module: Brando.Images.Image} = assets.database_image.opts
    assert %{cfg: :config_target, module: Brando.Files.File} = assets.target_file.opts
  end
end

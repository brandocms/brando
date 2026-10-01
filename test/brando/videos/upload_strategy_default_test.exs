defmodule Brando.Videos.UploadStrategyDefaultTest do
  # Video uploads are opt-in. A field that doesn't choose a strategy follows
  # `default_video_upload_strategy`, and a site that hasn't chosen one gets
  # `:none`, which can pick from the library or add by URL but not upload.
  use ExUnit.Case, async: false

  import Brando.Test.Support, only: [put_test_env: 2]

  alias Brando.Blueprint.AssetConfigNormalizer
  alias Brando.Type.VideoConfig

  defp field(cfg), do: %{type: :video, name: :cover_video, opts: %{cfg: cfg}}

  defp strategy(asset), do: AssetConfigNormalizer.normalize(asset).opts.cfg.upload_strategy

  test "without a configured default, nothing uploads" do
    put_test_env(:default_video_upload_strategy, nil)

    assert Brando.default_video_upload_strategy() == :none
    assert strategy(field(%VideoConfig{})) == :none
    refute Brando.Uploads.video_upload_available?(%VideoConfig{upload_strategy: :none})
  end

  test "a field without its own strategy follows the site's default" do
    put_test_env(:default_video_upload_strategy, :local)
    assert strategy(field(%VideoConfig{})) == :local

    put_test_env(:default_video_upload_strategy, :mux)
    assert strategy(field(%VideoConfig{})) == :mux
  end

  test "a field's own strategy wins over the default" do
    put_test_env(:default_video_upload_strategy, :mux)
    assert strategy(field(%VideoConfig{upload_strategy: :local})) == :local
  end

  test "deferred configs and gallery videos inherit too" do
    put_test_env(:default_video_upload_strategy, :local)

    assert strategy(field(fn -> %{upload_path: "videos/deferred"} end)) == :local

    gallery = %{type: :gallery, name: :gallery, opts: %{cfg: %{image: %{}, video: %VideoConfig{}}}}
    assert AssetConfigNormalizer.normalize(gallery).opts.cfg.video.upload_strategy == :local
  end
end

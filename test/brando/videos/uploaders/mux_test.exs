defmodule Brando.Videos.Uploaders.MuxTest do
  use ExUnit.Case, async: true

  alias Brando.Videos.Uploaders.Mux

  test "builds current Mux direct-upload asset settings" do
    config = %Brando.Type.VideoConfig{
      upload_strategy: :mux,
      meta: %{
        mux: %{
          "playback_policies" => ["public"],
          "static_renditions" => [%{"resolution" => "highest"}]
        }
      }
    }

    assert {:ok, settings} = Mux.build_asset_settings(config: config)
    assert settings["playback_policies"] == ["public"]
    assert settings["static_renditions"] == [%{"resolution" => "highest"}]
    refute Map.has_key?(settings, "playback_policy")
    refute Map.has_key?(settings, "mp4_support")
  end

  test "passes video quality through from config meta and direct opts" do
    config = %Brando.Type.VideoConfig{
      upload_strategy: :mux,
      meta: %{mux: %{"video_quality" => "basic"}}
    }

    assert {:ok, settings} = Mux.build_asset_settings(config: config)
    assert settings["video_quality"] == "basic"

    assert {:ok, overridden} = Mux.build_asset_settings(config: config, video_quality: "premium")
    assert overridden["video_quality"] == "premium"
  end

  test "translates legacy public settings without sending deprecated fields" do
    config = %Brando.Type.VideoConfig{
      upload_strategy: :mux,
      meta: %{mux: %{"playback_policy" => ["public"], "mp4_support" => "standard"}}
    }

    assert {:ok, settings} = Mux.build_asset_settings(config: config)
    assert settings["playback_policies"] == ["public"]
    assert settings["static_renditions"] == [%{"resolution" => "highest"}]
    refute Map.has_key?(settings, "playback_policy")
    refute Map.has_key?(settings, "mp4_support")
  end

  test "rejects signed playback until token signing is implemented" do
    config = %Brando.Type.VideoConfig{
      upload_strategy: :mux,
      meta: %{mux: %{"playback_policies" => ["signed"]}}
    }

    assert {:error, :signed_playback_not_supported} = Mux.build_asset_settings(config: config)

    video = %Brando.Videos.Video{
      type: :mux,
      status: :ready,
      meta: %{"mux" => %{"playback_id" => "signed-id", "playback_policy" => "signed"}}
    }

    assert {:error, :signed_playback_not_supported} = Mux.get_playback_url(video)
  end
end

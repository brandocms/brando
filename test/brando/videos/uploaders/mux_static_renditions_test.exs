defmodule Brando.Videos.Uploaders.MuxStaticRenditionsTest do
  @moduledoc """
  Mux static renditions: what new assets ask for, what Brando stores of them,
  the rendition webhooks, and asking Mux for them on existing assets. Mux is
  stubbed at the transport (`Req.Test`), as in `Brando.Videos.ProviderClientTest`.
  """
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Brando.Test.Support, only: [put_test_env: 2]
  import ExUnit.CaptureLog

  alias Brando.Factory
  alias Brando.Videos.Playback
  alias Brando.Videos.Uploaders.Mux

  setup do
    put_test_env(Brando.Videos, [])
    :ok
  end

  # Records each request as {method, path, body} and answers with `respond`
  defp stub_mux(respond) do
    test = self()

    Req.Test.stub(Mux, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      body = if body == "", do: nil, else: Jason.decode!(body)
      send(test, {:mux, conn.method, conn.request_path, body})
      {status, json} = respond.(conn.method, conn.request_path, body)

      conn
      |> Plug.Conn.put_status(status)
      |> Req.Test.json(json)
    end)

    put_test_env(Mux, access_token_id: "id", access_token_secret: "secret", req_options: [plug: {Req.Test, Mux}])
  end

  defp file(resolution, status), do: %{"id" => "r-#{resolution}", "resolution" => resolution, "status" => status}

  defp asset(id, files) do
    %{
      "id" => id,
      "status" => "ready",
      "playback_ids" => [%{"id" => "pb-#{id}", "policy" => "public"}],
      "static_renditions" => %{"files" => files}
    }
  end

  defp insert_mux(asset_id, extra \\ %{}) do
    user = Factory.insert(:random_user)

    Factory.insert(:video,
      creator: user,
      type: :mux,
      status: :ready,
      meta: %{
        "provider" => "mux",
        "mux" =>
          Map.merge(%{"asset_id" => asset_id, "playback_id" => "pb-#{asset_id}", "playback_policy" => "public"}, extra)
      }
    )
  end

  defp reload(video), do: Brando.Repo.get!(Brando.Videos.Video, video.id)

  describe "new assets" do
    test "ask for the configured renditions, 720p and 1080p by default" do
      assert {:ok, settings} = Mux.build_asset_settings([])
      assert settings["static_renditions"] == [%{"resolution" => "720p"}, %{"resolution" => "1080p"}]

      put_test_env(Brando.Videos, mux_static_renditions: [2160, "480p", 720, 999])
      assert {:ok, settings} = Mux.build_asset_settings([])
      assert settings["static_renditions"] == Enum.map(~w(480p 720p 2160p), &%{"resolution" => &1})
    end

    test "ask for none with an empty list, and a video config's renditions replace the list" do
      put_test_env(Brando.Videos, mux_static_renditions: [])
      assert {:ok, settings} = Mux.build_asset_settings([])
      refute Map.has_key?(settings, "static_renditions")

      put_test_env(Brando.Videos, [])
      config = %Brando.Type.VideoConfig{upload_strategy: :mux, meta: %{mux: %{"mp4_support" => "standard"}}}
      assert {:ok, settings} = Mux.build_asset_settings(config: config)
      assert settings["static_renditions"] == [%{"resolution" => "highest"}]
    end
  end

  describe "recording renditions" do
    test "an asset's ready report stores its renditions, and the ready ones become qualities" do
      _video = insert_mux("asset-1")

      payload = %{
        "type" => "video.asset.ready",
        "data" => asset("asset-1", [file("720p", "ready"), file("1080p", "preparing"), file("highest", "ready")])
      }

      assert {:ok, video} = Mux.handle_webhook(payload)

      assert [%{"resolution" => "720p", "status" => "ready", "id" => "r-720p"} | _] =
               video.meta["mux"]["static_renditions"]

      assert Playback.choices(video) == [:auto, :hls, :mp4_720]
    end

    test "a rendition's webhook reads the asset again and stores what Mux has now" do
      video = insert_mux("asset-2", %{"static_renditions" => [file("720p", "ready"), file("1080p", "preparing")]})

      stub_mux(fn "GET", "/video/v1/assets/asset-2", nil ->
        {200, %{"data" => asset("asset-2", [file("720p", "ready"), file("1080p", "ready")])}}
      end)

      payload = %{
        "type" => "video.asset.static_rendition.ready",
        "object" => %{"type" => "asset", "id" => "asset-2"},
        "data" => %{"id" => "r-1080p", "resolution" => "1080p", "status" => "ready", "name" => "1080p.mp4"}
      }

      assert {:ok, _video} = Mux.handle_webhook(payload)
      assert Playback.mp4_resolutions(reload(video)) == [720, 1080]
    end

    test "a late report of a rendition preparing doesn't undo it being ready" do
      _video = insert_mux("asset-3", %{"static_renditions" => [file("720p", "ready")]})

      payload = %{"type" => "video.asset.ready", "data" => asset("asset-3", [file("720p", "preparing")])}

      assert {:ok, video} = Mux.handle_webhook(payload)
      assert Playback.mp4_resolutions(video) == [720]
    end

    test "a rendition's webhook for an asset Brando doesn't hold is ignored" do
      payload = %{
        "type" => "video.asset.static_rendition.ready",
        "object" => %{"type" => "asset", "id" => "someone-elses"},
        "data" => %{"id" => "r-1", "resolution" => "720p", "status" => "ready"}
      }

      assert Mux.handle_webhook(payload) == :ignore
    end
  end

  describe "add_static_renditions/1" do
    test "asks Mux for the renditions an asset lacks, and stores what it has" do
      video = insert_mux("asset-4")
      skipped = insert_mux("asset-5")
      gone = insert_mux("asset-6")
      _signed = insert_mux("asset-7", %{"playback_policy" => "signed"})

      stub_mux(fn
        "GET", "/video/v1/assets/asset-4", nil ->
          files = [file("highest", "ready"), file("720p", "ready")]
          files = if Process.get(:added), do: files ++ [file("1080p", "preparing")], else: files
          {200, %{"data" => asset("asset-4", files)}}

        "POST", "/video/v1/assets/asset-4/static-renditions", %{"resolution" => "1080p"} ->
          Process.put(:added, true)
          {201, %{"data" => file("1080p", "preparing")}}

        # Mux skipped 1080p for a 720p source: nothing to ask for
        "GET", "/video/v1/assets/asset-5", nil ->
          {200, %{"data" => asset("asset-5", [file("720p", "ready"), file("1080p", "skipped")])}}

        "GET", "/video/v1/assets/asset-6", nil ->
          {404, %{"error" => %{"type" => "not_found"}}}
      end)

      results = capture_log(fn -> send(self(), {:results, Mux.add_static_renditions(interval: 0)}) end)
      assert results =~ "Mux API request failed"
      assert_received {:results, results}

      assert [four, five, six] = results
      assert %{video_id: id, present: [720], requested: [1080], failed: [], error: nil} = four
      assert id == video.id
      assert %{present: [720, 1080], requested: [], error: nil} = five
      assert %{requested: [], error: %{"error" => %{"type" => "not_found"}}} = six

      assert [%{"resolution" => "1080p", "status" => "preparing"}] =
               Enum.filter(reload(video).meta["mux"]["static_renditions"], &(&1["resolution"] == "1080p"))

      assert Playback.mp4_resolutions(reload(skipped)) == [720]
      assert reload(gone).meta == gone.meta

      refute_received {:mux, "GET", "/video/v1/assets/asset-7", _}
      refute_received {:mux, "POST", "/video/v1/assets/asset-5/static-renditions", _}
    end

    test "a dry run asks Mux for nothing and stores nothing" do
      video = insert_mux("asset-8")

      stub_mux(fn "GET", "/video/v1/assets/asset-8", nil -> {200, %{"data" => asset("asset-8", [])}} end)

      assert [%{requested: [720, 1080], present: []}] = Mux.add_static_renditions(dry_run: true)
      refute_received {:mux, "POST", _, _}
      assert reload(video).meta == video.meta
    end

    test "a refused request is reported, and the rest still asked for" do
      insert_mux("asset-9")

      stub_mux(fn
        "GET", "/video/v1/assets/asset-9", nil ->
          {200, %{"data" => asset("asset-9", [file("highest", "ready")])}}

        "POST", "/video/v1/assets/asset-9/static-renditions", %{"resolution" => "720p"} ->
          {400, %{"error" => %{"type" => "invalid_parameters"}}}

        "POST", "/video/v1/assets/asset-9/static-renditions", %{"resolution" => "1080p"} ->
          {201, %{"data" => file("1080p", "preparing")}}
      end)

      capture_log(fn -> send(self(), {:results, Mux.add_static_renditions(interval: 0)}) end)
      assert_received {:results, [result]}

      assert %{requested: [1080], failed: [{720, %{"error" => %{"type" => "invalid_parameters"}}}]} = result
    end
  end
end

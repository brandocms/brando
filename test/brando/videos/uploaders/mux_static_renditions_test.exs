defmodule Brando.Videos.Uploaders.MuxStaticRenditionsTest do
  @moduledoc """
  Mux static renditions: what new assets ask for, what Brando stores of them,
  the rendition webhooks, and asking Mux for them on existing assets. Mux is
  stubbed at the transport (`Req.Test`), as in `Brando.Videos.ProviderClientTest`,
  by an account that keeps its assets and refuses what Mux refuses.
  """
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Brando.Test.Support, only: [put_test_env: 2]
  import ExUnit.CaptureLog

  alias Brando.Content.Block
  alias Brando.Content.Var
  alias Brando.Factory
  alias Brando.Pages.Page
  alias Brando.Videos.Playback
  alias Brando.Videos.Uploaders.Mux
  alias Brando.Villain.Blocks.GalleryBlock
  alias Brando.Villain.Blocks.GalleryObjectOverride
  alias Brando.Villain.Blocks.VideoBlock
  alias Ecto.Adapters.SQL.Sandbox
  alias Plug.Conn

  @renderer Brando.Worker.EntryRenderer

  setup do
    put_test_env(Brando.Videos, [])
    :ok
  end

  # A Mux account holding `assets` (`id => asset/2`). It refuses what Mux's
  # guide says it refuses
  # (https://www.mux.com/docs/guides/enable-static-mp4-renditions): a
  # resolution beside the `highest` rendition, `highest` beside a resolution,
  # and any static rendition on an asset whose legacy `mp4_support` isn't
  # `none`. `answer` may answer a request first, else nil. Each request is
  # sent to the test as {:mux, method, path, body}.
  defp fake_mux(assets, answer \\ fn _method, _path, _body -> nil end) do
    test = self()
    account = start_supervised!({Agent, fn -> assets end}, id: make_ref())

    Req.Test.stub(Mux, fn conn ->
      {:ok, body, conn} = Conn.read_body(conn)
      body = if body == "", do: nil, else: Jason.decode!(body)
      send(test, {:mux, conn.method, conn.request_path, body})

      case answer.(conn.method, conn.request_path, body) ||
             Agent.get_and_update(account, &account_answer(&1, conn.method, conn.path_info, body)) do
        {204, _} -> Conn.send_resp(conn, 204, "")
        {status, json} -> conn |> Conn.put_status(status) |> Req.Test.json(json)
      end
    end)

    put_test_env(Mux, access_token_id: "id", access_token_secret: "secret", req_options: [plug: {Req.Test, Mux}])
    account
  end

  defp account_answer(assets, "GET", ["video", "v1", "assets", id], nil) do
    case assets do
      %{^id => asset} -> {{200, %{"data" => asset}}, assets}
      _ -> {not_found(), assets}
    end
  end

  defp account_answer(assets, "POST", ["video", "v1", "assets", id, "static-renditions"], %{"resolution" => resolution}) do
    with %{^id => asset} <- assets,
         :ok <- may_add(asset, resolution) do
      rendition = file(resolution, "preparing")
      {{201, %{"data" => rendition}}, update_files(assets, id, &(&1 ++ [rendition]))}
    else
      {:refused, message} -> {{400, %{"error" => %{"type" => "invalid_parameters", "messages" => [message]}}}, assets}
      _ -> {not_found(), assets}
    end
  end

  defp account_answer(assets, "DELETE", ["video", "v1", "assets", id, "static-renditions", rendition_id], nil) do
    if Map.has_key?(assets, id),
      do: {{204, nil}, update_files(assets, id, &Enum.reject(&1, fn file -> file["id"] == rendition_id end))},
      else: {not_found(), assets}
  end

  defp account_answer(assets, "PUT", ["video", "v1", "assets", id, "mp4-support"], %{"mp4_support" => "none"}) do
    case assets do
      %{^id => asset} ->
        asset = asset |> Map.put("mp4_support", "none") |> Map.delete("static_renditions")
        {{200, %{"data" => asset}}, Map.put(assets, id, asset)}

      _ ->
        {not_found(), assets}
    end
  end

  defp may_add(asset, resolution) do
    files = get_in(asset, ["static_renditions", "files"]) || []
    resolutions = Enum.map(files, & &1["resolution"])

    cond do
      asset["mp4_support"] not in [nil, "none"] ->
        {:refused, "mp4_support must be none"}

      resolution != "highest" and "highest" in resolutions ->
        {:refused, "cannot be mixed with highest"}

      resolution == "highest" and Enum.any?(resolutions, &(&1 not in [nil, "highest", "audio-only"])) ->
        {:refused, "mixed"}

      true ->
        :ok
    end
  end

  defp update_files(assets, id, fun) do
    Map.update!(assets, id, fn asset ->
      files = fun.(get_in(asset, ["static_renditions", "files"]) || [])
      Map.put(asset, "static_renditions", %{"files" => files})
    end)
  end

  defp not_found, do: {404, %{"error" => %{"type" => "not_found"}}}

  defp file(resolution, status), do: %{"id" => "r-#{resolution}", "resolution" => resolution, "status" => status}

  defp asset(id, files) do
    %{
      "id" => id,
      "status" => "ready",
      "playback_ids" => [%{"id" => "pb-#{id}", "policy" => "public"}],
      "static_renditions" => %{"files" => files},
      "aspect_ratio" => "16:9",
      "duration" => 30.0,
      "tracks" => [%{"type" => "video", "max_width" => 1920, "max_height" => 1080}]
    }
  end

  defp stored(files), do: Enum.map(files, &Map.put(&1, "name", nil))

  defp insert_mux(asset_id, extra \\ %{}, attrs \\ []) do
    user = Factory.insert(:random_user)

    # The factory's repo is Ecto's own, which doesn't read the tenant prefix
    prefix = Brando.Tenant.current_prefix()

    Factory.insert(
      :video,
      [
        creator: user,
        type: :mux,
        status: :ready,
        width: 800,
        height: 600,
        aspect_ratio: "4/3",
        duration: "00:12",
        meta: %{
          "provider" => "mux",
          "mux" =>
            Map.merge(%{"asset_id" => asset_id, "playback_id" => "pb-#{asset_id}", "playback_policy" => "public"}, extra)
        }
      ] ++ attrs,
      if(prefix, do: [prefix: prefix], else: [])
    )
  end

  # A Mux video the backfill gives renditions: an autoplaying loop on a page
  defp insert_loop(asset_id, extra \\ %{}) do
    video = insert_mux(asset_id, extra, autoplay: true, loop: true)
    video_ref(video, [])
    video
  end

  defp reload(video), do: Brando.Repo.get!(Brando.Videos.Video, video.id)

  # What another event stores: these resolutions ready
  defp store_ready(video, resolutions) do
    renditions = stored(Enum.map(resolutions, &file(&1, "ready")))
    meta = put_in(video.meta, ["mux", "static_renditions"], renditions)
    video |> Ecto.Changeset.change(meta: meta) |> Brando.Repo.update!()
  end

  defp rendition_event(asset_id, event \\ "ready") do
    %{
      "type" => "video.asset.static_rendition.#{event}",
      "object" => %{"type" => "asset", "id" => asset_id},
      "data" => %{"id" => "r-1080p", "resolution" => "1080p", "status" => event, "name" => "1080p.mp4"}
    }
  end

  # A page showing one block; returns the block
  defp page_block(title) do
    page = Factory.insert(:page, title: title, uri: Brando.Utils.slugify(title))
    Brando.Content.create_identifier(Page, page)
    source = "Elixir.Brando.Pages.Page.Blocks"
    block = Brando.Repo.insert!(%Block{type: :module, source: source, uid: Brando.Utils.generate_uid()})
    Brando.Repo.insert!(%Page.Blocks{entry_id: page.id, block_id: block.id, sequence: 0})
    {page, block}
  end

  defp video_ref(video, data) do
    {_page, block} = page_block("Shows #{video.id} #{System.unique_integer([:positive])}")

    Factory.insert(:ref,
      block_id: block.id,
      video_id: video.id,
      data: %VideoBlock{type: "video", data: struct(VideoBlock.Data, data)}
    )
  end

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

      config = %Brando.Type.VideoConfig{
        upload_strategy: :mux,
        meta: %{mux: %{"static_renditions" => [%{"resolution" => "480p"}]}}
      }

      assert {:ok, settings} = Mux.build_asset_settings(config: config)
      assert settings["static_renditions"] == [%{"resolution" => "480p"}]
    end

    test "a video config's legacy mp4_support asks for the configured renditions, not highest" do
      config = %Brando.Type.VideoConfig{upload_strategy: :mux, meta: %{mux: %{"mp4_support" => "standard"}}}
      assert {:ok, settings} = Mux.build_asset_settings(config: config)
      assert settings["static_renditions"] == [%{"resolution" => "720p"}, %{"resolution" => "1080p"}]
      refute Map.has_key?(settings, "mp4_support")

      put_test_env(Brando.Videos, mux_static_renditions: [480])
      assert {:ok, settings} = Mux.build_asset_settings(config: config)
      assert settings["static_renditions"] == [%{"resolution" => "480p"}]
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
      fake_mux(%{"asset-2" => asset("asset-2", [file("720p", "ready"), file("1080p", "ready")])})

      assert {:ok, _video} = Mux.handle_webhook(rendition_event("asset-2"))
      assert Playback.mp4_resolutions(reload(video)) == [720, 1080]
    end

    test "a rendition's webhook keeps the size, shape and duration the editor set" do
      video = insert_mux("asset-shape", %{"static_renditions" => [file("720p", "ready")]})
      fake_mux(%{"asset-shape" => asset("asset-shape", [file("720p", "ready"), file("1080p", "ready")])})

      assert {:ok, _video} = Mux.handle_webhook(rendition_event("asset-shape"))

      assert %{aspect_ratio: "4/3", width: 800, height: 600, duration: "00:12"} = reload(video)
      assert Playback.mp4_resolutions(reload(video)) == [720, 1080]
    end

    test "a rendition ready re-renders the entries showing the video; a report that changes nothing writes nothing" do
      video = insert_mux("asset-render", %{"static_renditions" => stored([file("720p", "ready")])})
      video_ref(video, autoplay: true)
      account = fake_mux(%{"asset-render" => asset("asset-render", [file("720p", "ready")])})

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _} = Mux.handle_webhook(rendition_event("asset-render"))
        assert reload(video).updated_at == video.updated_at
        refute_enqueued(worker: @renderer)

        # 1080p errored: stored, but the video plays what it did
        Agent.update(account, fn _ ->
          %{"asset-render" => asset("asset-render", [file("720p", "ready"), file("1080p", "errored")])}
        end)

        assert {:ok, _} = Mux.handle_webhook(rendition_event("asset-render", "errored"))
        assert [_, %{"status" => "errored"}] = reload(video).meta["mux"]["static_renditions"]
        refute_enqueued(worker: @renderer)

        Agent.update(account, fn _ ->
          %{"asset-render" => asset("asset-render", [file("720p", "ready"), file("1080p", "ready")])}
        end)

        assert {:ok, _} = Mux.handle_webhook(rendition_event("asset-render"))
        assert_enqueued(worker: @renderer)
      end)
    end

    test "a ready rendition another event stored while the asset was read stays ready" do
      video =
        insert_mux("asset-race", %{"static_renditions" => stored([file("720p", "ready"), file("1080p", "preparing")])})

      # The asset report is old, and while it is read another event stores 1080p ready
      fake_mux(%{}, fn "GET", "/video/v1/assets/asset-race", nil ->
        store_ready(video, ["720p", "1080p"])
        {200, %{"data" => asset("asset-race", [file("720p", "ready"), file("1080p", "preparing")])}}
      end)

      assert {:ok, _} = Mux.handle_webhook(rendition_event("asset-race"))
      assert Playback.mp4_resolutions(reload(video)) == [720, 1080]
    end

    # A row lock needs two connections, so this runs outside the sandbox
    test "a rendition's webhook waits for another event holding the row, and keeps what it stored" do
      preparing = stored([file("720p", "ready"), file("1080p", "preparing")])

      video =
        Sandbox.unboxed_run(Brando.Repo.repo(), fn ->
          Factory.insert(:video,
            type: :mux,
            status: :ready,
            meta: %{"provider" => "mux", "mux" => %{"asset_id" => "asset-lock", "static_renditions" => preparing}}
          )
        end)

      on_exit(fn -> Sandbox.unboxed_run(Brando.Repo.repo(), fn -> Brando.Repo.repo().delete!(video) end) end)

      # Mux's report is older than the other event: 1080p still preparing, and 480p asked for since
      fake_mux(%{
        "asset-lock" =>
          asset("asset-lock", [file("720p", "ready"), file("1080p", "preparing"), file("480p", "preparing")])
      })

      test = self()

      holder =
        Task.async(fn ->
          Sandbox.unboxed_run(Brando.Repo.repo(), fn ->
            Brando.Repo.transaction(fn ->
              from(v in Brando.Videos.Video, where: v.id == ^video.id, lock: "FOR UPDATE") |> Brando.Repo.one!()
              store_ready(video, ["720p", "1080p"])
              send(test, :holding)
              receive do: (:commit -> :ok), after: (5_000 -> raise "never told to commit")
            end)
          end)
        end)

      assert_receive :holding, 5_000

      webhook =
        Task.async(fn ->
          Sandbox.unboxed_run(Brando.Repo.repo(), fn -> Mux.handle_webhook(rendition_event("asset-lock")) end)
        end)

      refute Task.yield(webhook, 300)
      send(holder.pid, :commit)
      Task.await(holder)
      assert {:ok, _} = Task.await(webhook)

      renditions =
        Sandbox.unboxed_run(Brando.Repo.repo(), fn -> reload(video).meta["mux"]["static_renditions"] end)

      assert Map.new(renditions, &{&1["resolution"], &1["status"]}) ==
               %{"720p" => "ready", "1080p" => "ready", "480p" => "preparing"}
    end

    test "an asset's ready report keeps a rendition another event stored ready while it was read" do
      video =
        insert_mux("asset-ready-race", %{"static_renditions" => stored([file("720p", "preparing")])})

      payload = %{"type" => "video.asset.ready", "data" => asset("asset-ready-race", [file("720p", "preparing")])}

      # The report's holders are read, then a rendition's event stores 720p ready
      handler = "mux-ready-race-#{System.unique_integer()}"

      :telemetry.attach(
        handler,
        [:brando_integration, :repo, :query],
        fn _event, _measurements, %{source: source}, _ ->
          if source == "videos" do
            :telemetry.detach(handler)
            store_ready(video, ["720p"])
          end
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler) end)

      assert {:ok, _} = Mux.handle_webhook(payload)
      assert Playback.mp4_resolutions(reload(video)) == [720]
    end

    test "an upload's asset report keeps a rendition another event stored ready while the asset was read" do
      video =
        insert_mux("asset-upload-race", %{
          "upload_id" => "upload-race",
          "static_renditions" => stored([file("720p", "preparing")])
        })

      fake_mux(%{}, fn "GET", "/video/v1/assets/asset-upload-race", nil ->
        store_ready(video, ["720p"])
        {200, %{"data" => asset("asset-upload-race", [file("720p", "preparing")])}}
      end)

      event = %{
        "type" => "video.upload.asset_created",
        "data" => %{"id" => "upload-race", "asset_id" => "asset-upload-race"}
      }

      assert {:ok, _} = Mux.handle_webhook(event)
      assert Playback.mp4_resolutions(reload(video)) == [720]
    end

    for {shape, report} <- [
          {"no static_renditions", quote(do: Map.delete(asset("asset-del", []), "static_renditions"))},
          {"no files", quote(do: Map.put(asset("asset-del", []), "static_renditions", %{"status" => "disabled"}))},
          {"files: []", quote(do: asset("asset-del", []))}
        ] do
      test "a deleted last rendition (#{shape}) stores none, and the entries showing the video stream again" do
        video = insert_mux("asset-del", %{"static_renditions" => stored([file("720p", "ready")])})
        video_ref(video, autoplay: true)
        fake_mux(%{"asset-del" => unquote(report)})

        Oban.Testing.with_testing_mode(:manual, fn ->
          assert {:ok, _} = Mux.handle_webhook(rendition_event("asset-del", "deleted"))
          assert reload(video).meta["mux"]["static_renditions"] == []
          assert Playback.mp4_resolutions(reload(video)) == []
          assert_enqueued(worker: @renderer)
        end)
      end
    end

    test "a late or retried ready report, as Mux sent it, keeps the renditions stored since" do
      # Renditions added after the asset was ready (the backfill), and stored
      # by their own events; the asset's original ready report then comes again
      _video = insert_mux("asset-ready-late", %{"static_renditions" => stored([file("720p", "ready")])})

      for data <- [Map.delete(asset("asset-ready-late", []), "static_renditions"), asset("asset-ready-late", [])] do
        assert {:ok, video} = Mux.handle_webhook(%{"type" => "video.asset.ready", "data" => data})
        assert Playback.mp4_resolutions(video) == [720]
      end
    end

    test "a ready report for a video with no renditions stored takes the report's" do
      _video = insert_mux("asset-ready-first", %{})
      payload = %{"type" => "video.asset.ready", "data" => asset("asset-ready-first", [file("720p", "preparing")])}

      assert {:ok, video} = Mux.handle_webhook(payload)
      assert [%{"resolution" => "720p", "status" => "preparing"}] = video.meta["mux"]["static_renditions"]
    end

    test "a webhook for a video deleted from the database meanwhile is ignored" do
      video =
        insert_mux("asset-hard", %{"upload_id" => "upload-hard", "static_renditions" => stored([file("720p", "ready")])})

      fake_mux(%{}, fn "GET", "/video/v1/assets/asset-hard", nil ->
        Brando.Repo.delete!(video)
        {200, %{"data" => asset("asset-hard", [file("720p", "ready"), file("1080p", "ready")])}}
      end)

      assert Mux.handle_webhook(rendition_event("asset-hard")) == :ignore

      video = insert_mux("asset-hard", %{"upload_id" => "upload-hard"})

      fake_mux(%{}, fn "GET", "/video/v1/assets/asset-hard", nil ->
        Brando.Repo.delete!(video)
        {200, %{"data" => asset("asset-hard", [])}}
      end)

      event = %{"type" => "video.upload.asset_created", "data" => %{"id" => "upload-hard", "asset_id" => "asset-hard"}}
      assert Mux.handle_webhook(event) == :ignore
    end

    test "a late report of a rendition preparing doesn't undo it being ready" do
      _video = insert_mux("asset-3", %{"static_renditions" => [file("720p", "ready")]})

      payload = %{"type" => "video.asset.ready", "data" => asset("asset-3", [file("720p", "preparing")])}

      assert {:ok, video} = Mux.handle_webhook(payload)
      assert Playback.mp4_resolutions(video) == [720]
    end

    test "a rendition's webhook for an asset Brando doesn't hold is ignored" do
      assert Mux.handle_webhook(rendition_event("someone-elses")) == :ignore
    end

    test "a rendition's webhook for an asset Mux no longer has is ignored, so Mux doesn't retry it" do
      video = insert_mux("asset-gone", %{"static_renditions" => [file("720p", "ready")]})
      fake_mux(%{})

      capture_log(fn -> send(self(), {:result, Mux.handle_webhook(rendition_event("asset-gone"))}) end)
      assert_received {:result, :ignore}
      assert reload(video).meta == video.meta
    end
  end

  describe "add_static_renditions/1" do
    test "asks Mux for the renditions an asset lacks, and stores only what it has" do
      video = insert_loop("asset-4")
      skipped = insert_loop("asset-5")
      gone = insert_loop("asset-6")
      _signed = insert_loop("asset-7", %{"playback_policy" => "signed"})

      fake_mux(%{
        "asset-4" => asset("asset-4", [file("720p", "ready")]),
        # Mux skipped 1080p for a 720p source: nothing to ask for
        "asset-5" => asset("asset-5", [file("720p", "ready"), file("1080p", "skipped")])
      })

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

      assert %{aspect_ratio: "4/3", width: 800, height: 600, duration: "00:12"} = reload(video)
      assert Playback.mp4_resolutions(reload(skipped)) == [720]
      assert reload(gone).meta == gone.meta

      refute_received {:mux, "GET", "/video/v1/assets/asset-7", _}
      refute_received {:mux, "POST", "/video/v1/assets/asset-5/static-renditions", _}
    end

    test "writes nothing for a video whose renditions it already has" do
      video = insert_loop("asset-same", %{"static_renditions" => stored([file("720p", "ready"), file("1080p", "ready")])})
      video_ref(video, autoplay: true)
      fake_mux(%{"asset-same" => asset("asset-same", [file("720p", "ready"), file("1080p", "ready")])})

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert [%{requested: [], error: nil}] = Mux.add_static_renditions(interval: 0)
        assert reload(video).updated_at == video.updated_at
        refute_enqueued(worker: @renderer)
      end)
    end

    test "a dry run asks Mux for nothing and stores nothing" do
      video = insert_loop("asset-8")
      fake_mux(%{"asset-8" => asset("asset-8", [])})

      assert [%{requested: [720, 1080], present: [], clear: []}] = Mux.add_static_renditions(dry_run: true)
      refute_received {:mux, "POST", _, _}
      assert reload(video).meta == video.meta
    end

    test "a refused request is reported, and the rest still asked for" do
      insert_loop("asset-9")

      fake_mux(%{"asset-9" => asset("asset-9", [])}, fn
        "POST", "/video/v1/assets/asset-9/static-renditions", %{"resolution" => "720p"} ->
          {400, %{"error" => %{"type" => "invalid_parameters"}}}

        _method, _path, _body ->
          nil
      end)

      capture_log(fn -> send(self(), {:results, Mux.add_static_renditions(interval: 0)}) end)
      assert_received {:results, [result]}

      assert %{requested: [1080], failed: [{720, %{"error" => %{"type" => "invalid_parameters"}}}]} = result
    end

    test "logs each video's result, for a release's rpc" do
      insert_loop("asset-log")
      fake_mux(%{"asset-log" => asset("asset-log", [file("720p", "ready")])})

      previous = Logger.level()
      Logger.configure(level: :info)
      on_exit(fn -> Logger.configure(level: previous) end)
      log = capture_log([level: :info], fn -> Mux.add_static_renditions(interval: 0) end)
      assert log =~ "asset-log"
      assert log =~ "1080p"
    end
  end

  describe "add_static_renditions/1 on assets with highest or legacy mp4_support" do
    test "a dry run lists what it would remove first" do
      insert_loop("asset-h", %{})
      insert_loop("asset-l", %{})

      fake_mux(%{
        "asset-h" => asset("asset-h", [file("highest", "ready")]),
        "asset-l" =>
          "asset-l"
          |> asset([])
          |> Map.merge(%{
            "mp4_support" => "standard",
            "static_renditions" => %{"status" => "ready", "files" => [%{"name" => "low.mp4"}]}
          })
      })

      assert [%{clear: [:highest], requested: [720, 1080]}, %{clear: [:mp4_support], requested: [720, 1080]}] =
               Mux.add_static_renditions(dry_run: true)

      refute_received {:mux, "DELETE", _, _}
      refute_received {:mux, "PUT", _, _}
    end

    test "with apply, removes highest first, then asks for the resolutions" do
      video = insert_loop("asset-h2", %{"static_renditions" => stored([file("highest", "ready")])})
      fake_mux(%{"asset-h2" => asset("asset-h2", [file("highest", "ready")])})

      assert [%{clear: [:highest], requested: [720, 1080], failed: [], error: nil}] =
               Mux.add_static_renditions(interval: 0)

      assert_received {:mux, "DELETE", "/video/v1/assets/asset-h2/static-renditions/r-highest", _}
      assert [%{"resolution" => "720p"}, %{"resolution" => "1080p"}] = reload(video).meta["mux"]["static_renditions"]
    end

    test "with apply, turns legacy mp4_support off first, then asks for the resolutions" do
      insert_loop("asset-l2")

      fake_mux(%{
        "asset-l2" =>
          "asset-l2"
          |> asset([])
          |> Map.merge(%{
            "mp4_support" => "standard",
            "static_renditions" => %{"status" => "ready", "files" => [%{"name" => "low.mp4"}]}
          })
      })

      assert [%{clear: [:mp4_support], requested: [720, 1080], failed: [], error: nil}] =
               Mux.add_static_renditions(interval: 0)

      assert_received {:mux, "PUT", "/video/v1/assets/asset-l2/mp4-support", %{"mp4_support" => "none"}}
    end

    test "a refused removal asks for nothing on that asset, and the next asset still migrates" do
      insert_loop("asset-h3")
      insert_loop("asset-h4")

      fake_mux(
        %{
          "asset-h3" => asset("asset-h3", [file("highest", "ready")]),
          "asset-h4" => asset("asset-h4", [file("highest", "ready")])
        },
        fn
          "DELETE", "/video/v1/assets/asset-h3/static-renditions/r-highest", _ ->
            {500, %{"error" => %{"type" => "server"}}}

          _method, _path, _body ->
            nil
        end
      )

      capture_log(fn -> send(self(), {:results, Mux.add_static_renditions(interval: 0)}) end)
      assert_received {:results, [three, four]}

      assert %{clear: [], requested: [], error: {:clear, :highest, %{"error" => %{"type" => "server"}}}} = three
      assert %{clear: [:highest], requested: [720, 1080], error: nil} = four
      refute_received {:mux, "POST", "/video/v1/assets/asset-h3/static-renditions", _}
    end

    test "a failed read after the changes still reports what was changed" do
      insert_loop("asset-h6")
      reads = :counters.new(1, [])

      fake_mux(%{"asset-h6" => asset("asset-h6", [file("highest", "ready")])}, fn
        "GET", "/video/v1/assets/asset-h6", _ ->
          :counters.add(reads, 1, 1)
          if :counters.get(reads, 1) > 1, do: {500, %{"error" => %{"type" => "server"}}}

        _method, _path, _body ->
          nil
      end)

      capture_log(fn -> send(self(), {:results, Mux.add_static_renditions(interval: 0)}) end)
      assert_received {:results, [result]}
      assert %{clear: [:highest], requested: [720, 1080], error: %{"error" => %{"type" => "server"}}} = result

      description = Mux.describe_result(result, true)
      assert description =~ "removed the highest rendition"
      assert description =~ "asked for 720p, 1080p"
      assert description =~ "FAILED"
    end

    test "a failed save of what a read asset has is reported as that, not as a failed read" do
      result = %{clear: [], requested: [], failed: [], error: {:store, :changeset}}
      assert Mux.describe_result(result, true) == "FAILED to store what the asset has: :changeset"

      description = Mux.describe_result(%{result | clear: [:highest]}, true)
      assert description =~ "removed the highest rendition"
      assert description =~ "then FAILED to store what the asset has: :changeset"
    end

    test "a removal followed by a refused request is reported as half done" do
      insert_loop("asset-h5")

      fake_mux(%{"asset-h5" => asset("asset-h5", [file("highest", "ready")])}, fn
        "POST", "/video/v1/assets/asset-h5/static-renditions", _ -> {500, %{"error" => %{"type" => "server"}}}
        _method, _path, _body -> nil
      end)

      capture_log(fn -> send(self(), {:results, Mux.add_static_renditions(interval: 0)}) end)
      assert_received {:results, [result]}
      assert %{clear: [:highest], requested: [], failed: [{720, _}, {1080, _}]} = result
    end
  end

  describe "add_static_renditions/1 gives renditions only to videos that would play one" do
    test "an autoplay loop placement or a fixed MP4 quality qualifies; a video that only streams is skipped" do
      loop_ref = insert_mux("q-loop-ref")
      video_ref(loop_ref, autoplay: true, loop: true)

      watched_ref = insert_mux("q-watched-ref", %{}, autoplay: true)
      video_ref(watched_ref, controls: true)

      play_button = insert_mux("q-play-button")
      video_ref(play_button, autoplay: false, play_button: true)

      hls_ref = insert_mux("q-hls-ref", %{}, autoplay: true, loop: true)
      video_ref(hls_ref, quality: :hls)

      _fixed_on_video = insert_mux("q-fixed-video", %{}, quality: :mp4_720)
      fixed_on_ref = insert_mux("q-fixed-ref", %{}, controls: true)
      video_ref(fixed_on_ref, quality: :mp4_1080)

      _unused_loop = insert_mux("q-unused-loop", %{}, autoplay: true, loop: true)

      in_var = insert_mux("q-var", %{}, autoplay: true, loop: true)
      page = Factory.insert(:page, title: "Var page", uri: "var-page")

      Brando.Repo.insert!(%Var{
        type: :video,
        key: "loop",
        label: %{"en" => "Loop"},
        page_id: page.id,
        video_id: in_var.id
      })

      in_gallery = insert_mux("q-gallery")
      gallery = Factory.insert(:gallery)
      Factory.insert(:gallery_object, gallery_id: gallery.id, video_id: in_gallery.id)
      {_page, block} = page_block("Gallery page")

      Factory.insert(:ref,
        block_id: block.id,
        gallery_id: gallery.id,
        data: %GalleryBlock{
          type: "gallery",
          data: %GalleryBlock.Data{
            gallery_object_overrides: [
              %GalleryObjectOverride{
                object_id: "#{in_gallery.id}",
                object_type: :video,
                autoplay: true,
                use_default_autoplay: false
              }
            ]
          }
        }
      )

      ids = ~w(q-loop-ref q-watched-ref q-play-button q-hls-ref q-fixed-video q-fixed-ref q-unused-loop q-var q-gallery)
      fake_mux(Map.new(ids, &{&1, asset(&1, [])}))

      results = Map.new(Mux.add_static_renditions(dry_run: true), &{&1.asset_id, &1})

      for id <- ~w(q-loop-ref q-fixed-video q-fixed-ref q-var q-gallery),
          do: assert(%{skipped: nil, requested: [720, 1080]} = results[id], id)

      for id <- ~w(q-watched-ref q-play-button q-hls-ref q-unused-loop),
          do: assert(%{skipped: :streams, requested: []} = results[id], id)

      refute_received {:mux, "GET", "/video/v1/assets/q-unused-loop", _}
    end
  end

  describe "add_static_renditions/1 reads a gallery's settings as the renderer does" do
    # The gallery block's override applies first, then the gallery object's
    # config on top (`Brando.Villain.Parser`)
    defp in_gallery(asset_id, config, override) do
      video = insert_mux(asset_id)
      gallery = Factory.insert(:gallery)
      Factory.insert(:gallery_object, gallery_id: gallery.id, video_id: video.id, config: config)
      {_page, block} = page_block("Gallery #{asset_id}")

      Factory.insert(:ref,
        block_id: block.id,
        gallery_id: gallery.id,
        data: %GalleryBlock{
          type: "gallery",
          data: %GalleryBlock.Data{
            gallery_object_overrides: [
              struct(GalleryObjectOverride, Map.merge(%{object_id: "#{video.id}", object_type: :video}, override))
            ]
          }
        }
      )

      video
    end

    test "the object's config wins over the gallery block's override, either way" do
      in_gallery("g-config-off", %{"autoplay" => false}, %{autoplay: true, use_default_autoplay: false})
      in_gallery("g-config-on", %{"autoplay" => true}, %{autoplay: false, use_default_autoplay: false})
      in_gallery("g-config-hls", %{"quality" => "hls"}, %{quality: :mp4_720, autoplay: true, use_default_autoplay: false})

      fake_mux(Map.new(~w(g-config-off g-config-on g-config-hls), &{&1, asset(&1, [])}))
      results = Map.new(Mux.add_static_renditions(dry_run: true), &{&1.asset_id, &1})

      assert %{skipped: :streams} = results["g-config-off"]
      assert %{skipped: nil, requested: [720, 1080]} = results["g-config-on"]
      assert %{skipped: :streams} = results["g-config-hls"]
    end
  end

  describe "in multi-site mode" do
    defmodule Migrator do
      @moduledoc false
      @behaviour Brando.Environments.Migrator

      @impl true
      def migrate(_site, _environment), do: {:ok, []}
    end

    @describetag :tmp_dir

    setup %{tmp_dir: dir} do
      put_test_env(:media_path, Path.join(dir, "media"))
      put_test_env(:sites_path, Path.join(dir, "sites"))
      put_test_env(:tenant_migrator, Migrator)
      put_test_env(:tenant_structure_cloner, Brando.TenantCloners)
      put_test_env(:environment_schema_cloner, Brando.TenantCloners)
      put_test_env(:tenancy_mode, :multi)
      Brando.Tenant.put_prefix(nil)
      Brando.Tenant.Cache.clear()

      on_exit(fn ->
        Brando.Tenant.put_prefix(nil)
        Brando.Tenant.Cache.clear()
      end)

      creator = Factory.insert(:random_user, role: :superuser, avatar: nil)

      {:ok, _site} =
        Brando.Tenant.Setup.create_site(
          %{name: "Acme", key: "acme", languages: ["en"], default_language: "en", status: :active},
          creator,
          environments: [
            %{name: "Production", key: "production", live: true, domain: "acme.test"},
            %{name: "Staging", key: "staging", live: false, domain: "staging.acme.test"}
          ]
        )

      :ok
    end

    test "a webhook updates the asset in each environment holding it" do
      [production, staging] =
        for prefix <- ~w(tenant_acme_production tenant_acme_staging) do
          Brando.Tenant.with_prefix(prefix, fn -> insert_mux("asset-env", %{"static_renditions" => []}) end)
        end

      fake_mux(%{"asset-env" => asset("asset-env", [file("720p", "ready")])})

      assert {:ok, _} = Mux.handle_webhook(rendition_event("asset-env"))

      for {prefix, video} <- [{"tenant_acme_production", production}, {"tenant_acme_staging", staging}] do
        Brando.Tenant.with_prefix(prefix, fn -> assert Playback.mp4_resolutions(reload(video)) == [720] end)
      end

      ready = %{"type" => "video.asset.errored", "data" => %{"id" => "asset-env"}}
      assert {:ok, _} = Mux.handle_webhook(ready)

      Brando.Tenant.with_prefix("tenant_acme_staging", fn -> assert reload(staging).status == :errored end)
    end

    test "a webhook for an asset no environment holds is ignored" do
      fake_mux(%{})
      assert Mux.handle_webhook(rendition_event("nobodys")) == :ignore
    end
  end
end

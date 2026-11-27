defmodule BrandoWeb.Plugs.VideoWebhooksMultiSiteTest do
  @moduledoc """
  A Bunny or Cloudflare Stream webhook names the remote video, not where
  Brando holds it: it reaches the plug with no tenant prefix, and updates the
  video in every environment holding it, under that environment's prefix
  (#4017), as Mux's does.

  Site Acme has a production, a staging and a preview environment, each a
  schema with the content tables. Videos in different environments share no
  id sequence, so a test gives the video in one the id of the video in
  another.
  """
  # Synchronous: provider settings are the application's, and the
  # environments' schemas have fixed names.
  use Brando.ConnCase, async: false

  import Brando.Test.Support, only: [put_test_env: 2]
  import ExUnit.CaptureLog
  import Plug.Conn

  alias Brando.Assets.ProcessingStatus
  alias Brando.Repo
  alias Brando.Tenant
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry
  alias Brando.Videos
  alias Brando.Videos.Uploaders.Bunny
  alias Brando.Videos.Uploaders.Cloudflare
  alias Brando.Videos.Video
  alias BrandoWeb.Plugs.BunnyWebhook
  alias BrandoWeb.Plugs.CloudflareStreamWebhook
  alias Ecto.Adapters.SQL

  @bunny_secret "bunny-read-only-api-key"
  @cloudflare_secret "cloudflare-signing-secret"
  @guid "6f2c1a3e-1111-2222-3333-444455556666"
  @uid "cf0123456789abcdef0123456789abcd"

  @production "tenant_hooks_production"
  @staging "tenant_hooks_staging"
  @preview "tenant_hooks_preview"

  setup do
    put_test_env(:tenancy_mode, :multi)
    put_test_env(Cloudflare, webhook_secret: @cloudflare_secret)

    put_test_env(Bunny,
      api_key: "key",
      library_id: "133",
      webhook_secret: @bunny_secret,
      req_options: [plug: {Req.Test, Bunny}]
    )

    me = self()

    Req.Test.stub(Bunny, fn conn ->
      send(me, {:bunny, conn.method, conn.request_path})
      Req.Test.json(conn, bunny_details())
    end)

    Tenant.put_prefix(nil)
    Cache.clear()

    on_exit(fn ->
      Tenant.put_prefix(nil)
      Cache.clear()
    end)

    site("Acme", "hooks", ~w(production staging preview))
    :ok
  end

  describe "a Bunny webhook" do
    test "updates the video in each environment holding it, and only there" do
      production = insert(@production, bunny_video("Production clip"))
      staging = insert(@staging, %{bunny_video("Staging clip") | id: production.id})
      preview = insert(@preview, %{bunny_video("Preview clip", "another-guid") | id: production.id})

      assert bunny(1).status == 200

      assert status(@production, production) == :processing
      assert status(@staging, staging) == :processing
      assert status(@preview, preview) == :uploading
    end

    test "that finished reads Bunny's details once and stores them in each holder" do
      production = insert(@production, bunny_video("Production clip"))
      staging = insert(@staging, %{bunny_video("Staging clip") | id: production.id})

      assert bunny(3).status == 200

      assert_received {:bunny, "GET", "/library/133/videos/" <> @guid}
      refute_received {:bunny, _method, _path}

      for {prefix, video} <- [{@production, production}, {@staging, staging}] do
        stored = reload(prefix, video)
        assert %Video{status: :ready, width: 1920, height: 1080, aspect_ratio: "1920/1080"} = stored

        assert %{
                 "thumbnail_url" => "custom.jpg",
                 "available_resolutions" => "720p,1080p",
                 "has_mp4_fallback" => true
               } = stored.meta["bunny"]
      end
    end

    @tag :capture_log
    test "that finished marks each holder ready when Bunny's details can't be read" do
      me = self()

      Req.Test.stub(Bunny, fn conn ->
        send(me, {:bunny, conn.method, conn.request_path})
        conn |> put_status(404) |> Req.Test.json(%{"Message" => "Not Found"})
      end)

      production = insert(@production, bunny_video("Production clip"))
      staging = insert(@staging, %{bunny_video("Staging clip") | id: production.id})

      assert bunny(3).status == 200

      assert_received {:bunny, "GET", _path}
      refute_received {:bunny, _method, _path}

      for {prefix, video} <- [{@production, production}, {@staging, staging}] do
        stored = reload(prefix, video)
        assert stored.status == :ready
        assert stored.meta["bunny"] == %{"video_guid" => @guid}
      end
    end

    test "for a video no environment holds is ignored" do
      insert(@production, bunny_video("Production clip", "another-guid"))

      conn = bunny(3)
      assert conn.status == 200
      assert Jason.decode!(conn.resp_body) == %{"status" => "ignored"}
      refute_received {:bunny, _method, _path}
    end

    test "reaches the editors following the video in each holder, on both topics, and no one else" do
      production = insert(@production, bunny_video("Production clip"))
      _staging = insert(@staging, %{bunny_video("Staging clip") | id: production.id})
      _preview = insert(@preview, %{bunny_video("Preview clip", "another-guid") | id: production.id})
      for prefix <- [@production, @staging, @preview], do: follow(prefix, production.id)

      assert bunny(1).status == 200

      for topic <- [:form, :processing] do
        assert_receive {:heard, @production, ^topic, %Video{title: "Production clip"}}
        assert_receive {:heard, @staging, ^topic, %Video{title: "Staging clip"}}
      end

      settle()
      refute_received {:heard, _prefix, _topic, _video}
    end
  end

  describe "a Cloudflare Stream webhook" do
    test "updates the video in each environment holding it, and only there" do
      production = insert(@production, cloudflare_video("Production clip"))
      staging = insert(@staging, %{cloudflare_video("Staging clip") | id: production.id})
      preview = insert(@preview, %{cloudflare_video("Preview clip", "another-uid") | id: production.id})

      assert cloudflare(ready_payload()).status == 200

      for {prefix, video} <- [{@production, production}, {@staging, staging}] do
        stored = reload(prefix, video)
        assert %Video{status: :ready, width: 1280, height: 720} = stored
        assert stored.meta["cloudflare"]["playback_hls"] == "https://stream.test/#{@uid}/manifest/video.m3u8"
      end

      assert status(@preview, preview) == :uploading
    end

    test "for a video no environment holds is ignored" do
      insert(@production, cloudflare_video("Production clip", "another-uid"))

      conn = cloudflare(ready_payload())
      assert conn.status == 200
      assert Jason.decode!(conn.resp_body) == %{"status" => "ignored"}
    end

    test "reaches the editors following the video in each holder, on both topics, and no one else" do
      production = insert(@production, cloudflare_video("Production clip"))
      _staging = insert(@staging, %{cloudflare_video("Staging clip") | id: production.id})
      _preview = insert(@preview, %{cloudflare_video("Preview clip", "another-uid") | id: production.id})
      for prefix <- [@production, @staging, @preview], do: follow(prefix, production.id)

      assert cloudflare(ready_payload()).status == 200

      for topic <- [:form, :processing] do
        assert_receive {:heard, @production, ^topic, %Video{title: "Production clip", status: :ready}}
        assert_receive {:heard, @staging, ^topic, %Video{title: "Staging clip", status: :ready}}
      end

      settle()
      refute_received {:heard, _prefix, _topic, _video}
    end
  end

  # Each case holds the video in one healthy environment, staging, beside
  # the one it is about
  for provider <- [:bunny, :cloudflare] do
    describe "a #{provider} webhook beside a healthy holder" do
      @describetag provider: provider

      test "skips an environment whose video table isn't there yet", %{provider: provider} do
        staging = insert(@staging, provider_video(provider))
        SQL.query!(Repo.repo(), ~s|DROP TABLE "#{@production}".videos CASCADE|)

        assert deliver(provider).status == 200
        assert status(@staging, staging) == expected_status(provider)
      end

      @tag :capture_log
      test "updates the others when one holder's write raises, and answers with an error", %{provider: provider} do
        production = insert(@production, provider_video(provider))
        staging = insert(@staging, %{provider_video(provider) | id: production.id})
        refuse_updates(@production)

        log = capture_log(fn -> assert deliver(provider).status == 422 end)
        assert log =~ "Could not apply a provider's report to video #{production.id}"

        assert status(@staging, staging) == expected_status(provider)
        assert status(@production, production) == :uploading
      end

      @tag :capture_log
      test "answers a holdings read that fails with an error, not as nothing to update", %{provider: provider} do
        insert(@staging, provider_video(provider))
        environment(Registry.get_site_by_key("hooks"), "broken", tables: :unreadable)

        conn = deliver(provider)
        assert conn.status == 422
      end

      test "leaves a suspended site's copy as it was", %{provider: provider} do
        staging = insert(@staging, provider_video(provider))
        other = site("Other", "hooks-other", ~w(production))
        other_video = insert("tenant_hooks-other_production", provider_video(provider))
        {:ok, _other} = Registry.update_site(other, %{status: :suspended})

        assert deliver(provider).status == 200
        assert status(@staging, staging) == expected_status(provider)
        assert status("tenant_hooks-other_production", other_video) == :uploading
      end

      test "leaves a soft-deleted copy as it was", %{provider: provider} do
        staging = insert(@staging, provider_video(provider))
        deleted = insert(@production, %{provider_video(provider) | deleted_at: DateTime.utc_now(:second)})

        assert deliver(provider).status == 200
        assert status(@staging, staging) == expected_status(provider)
        assert status(@production, deleted) == :uploading
      end

      test "in single-site mode updates only the configured site's environments", %{provider: provider} do
        put_test_env(:tenancy_mode, :single)
        put_test_env(:site_key, "hooks")
        staging = insert(@staging, provider_video(provider))
        site("Other", "hooks-other", ~w(production))
        other_video = insert("tenant_hooks-other_production", provider_video(provider))

        assert deliver(provider).status == 200
        assert status(@staging, staging) == expected_status(provider)
        assert status("tenant_hooks-other_production", other_video) == :uploading
      end
    end
  end

  defp deliver(:bunny), do: bunny(1)
  defp deliver(:cloudflare), do: cloudflare(ready_payload())

  defp expected_status(:bunny), do: :processing
  defp expected_status(:cloudflare), do: :ready

  defp provider_video(:bunny), do: bunny_video("Clip")
  defp provider_video(:cloudflare), do: cloudflare_video("Clip")

  # A signed delivery through the plug, with no tenant prefix
  defp bunny(status) do
    body = Jason.encode!(%{"VideoLibraryId" => 133, "VideoGuid" => @guid, "Status" => status})
    signature = :hmac |> :crypto.mac(:sha256, @bunny_secret, body) |> Base.encode16(case: :lower)

    :post
    |> Plug.Test.conn("/api/videos/bunny/webhook", body)
    |> put_req_header("x-bunnystream-signature-version", "v1")
    |> put_req_header("x-bunnystream-signature-algorithm", "hmac-sha256")
    |> put_req_header("x-bunnystream-signature", signature)
    |> BunnyWebhook.call(BunnyWebhook.init(mount: ["api", "videos", "bunny", "webhook"]))
  end

  defp cloudflare(payload) do
    body = Jason.encode!(payload)
    time = System.system_time(:second)
    signature = :hmac |> :crypto.mac(:sha256, @cloudflare_secret, "#{time}.#{body}") |> Base.encode16(case: :lower)

    :post
    |> Plug.Test.conn("/api/videos/cloudflare/webhook", body)
    |> put_req_header("webhook-signature", "time=#{time},sig1=#{signature}")
    |> CloudflareStreamWebhook.call(CloudflareStreamWebhook.init(mount: ["api", "videos", "cloudflare", "webhook"]))
  end

  defp ready_payload do
    %{
      "uid" => @uid,
      "readyToStream" => true,
      "status" => %{"state" => "ready"},
      "playback" => %{"hls" => "https://stream.test/#{@uid}/manifest/video.m3u8"},
      "input" => %{"width" => 1280, "height" => 720},
      "duration" => 12.5
    }
  end

  defp bunny_details do
    %{
      "guid" => @guid,
      "videoLibraryId" => 133,
      "status" => 3,
      "length" => 12,
      "availableResolutions" => "720p,1080p",
      "hasMP4Fallback" => true,
      "thumbnailFileName" => "custom.jpg",
      "width" => 1920,
      "height" => 1080
    }
  end

  defp bunny_video(title, guid \\ @guid) do
    %Video{
      type: :bunny,
      title: title,
      status: :uploading,
      meta: %{"provider" => "bunny", "bunny" => %{"video_guid" => guid}}
    }
  end

  defp cloudflare_video(title, uid \\ @uid) do
    %Video{
      type: :cloudflare,
      title: title,
      status: :uploading,
      remote_id: uid,
      meta: %{"provider" => "cloudflare", "cloudflare" => %{"uid" => uid}}
    }
  end

  defp insert(prefix, video), do: Tenant.with_prefix(prefix, fn -> Repo.insert!(video) end)
  defp reload(prefix, video), do: Tenant.with_prefix(prefix, fn -> Repo.get!(Video, video.id) end)
  defp status(prefix, video), do: reload(prefix, video).status

  defp refuse_updates(prefix) do
    SQL.query!(
      Repo.repo(),
      ~s|CREATE FUNCTION "#{prefix}".refuse() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'refused'; END $$|
    )

    SQL.query!(
      Repo.repo(),
      ~s|CREATE TRIGGER refuse BEFORE UPDATE ON "#{prefix}".videos FOR EACH ROW EXECUTE FUNCTION "#{prefix}".refuse()|
    )
  end

  defp site(name, key, environments) do
    {:ok, site} =
      Registry.create_site(%{
        name: name,
        key: key,
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :dynamic
      })

    Enum.each(environments, &environment(site, &1))
    Registry.get_site(site.id)
  end

  # The content tables' structure, as an environment has them. With
  # `tables: :unreadable`, a `videos` table the holdings cannot read.
  defp environment(site, key, opts \\ []) do
    {:ok, environment} = Registry.create_environment(site, %{name: key, key: key, live: key == "production"})
    prefix = Tenant.prefix(site, environment)
    SQL.query!(Repo.repo(), ~s(CREATE SCHEMA "#{prefix}"))

    case Keyword.get(opts, :tables, true) do
      true -> Enum.each(content_tables(), &clone_table(prefix, &1))
      :unreadable -> SQL.query!(Repo.repo(), ~s|CREATE TABLE "#{prefix}"."videos" (id bigint)|)
    end

    environment
  end

  defp content_tables do
    %{rows: rows} = SQL.query!(Repo.repo(), "SELECT tablename FROM pg_tables WHERE schemaname = 'public'")
    rows |> List.flatten() |> Enum.reject(&Tenant.SharedTables.member?/1)
  end

  defp clone_table(prefix, table) do
    escaped = String.replace(table, "\"", "\"\"")
    SQL.query!(Repo.repo(), ~s|CREATE TABLE "#{prefix}"."#{escaped}" (LIKE public."#{escaped}" INCLUDING ALL)|)
  end

  # A process following video `id` in `prefix` on both topics editors
  # follow a video on: the form's (`Brando.Videos.video_topic/1`) and the
  # processing status's. It sends the test each update it hears.
  defp follow(prefix, id) do
    test = self()

    {:ok, pid} =
      Task.start_link(fn ->
        Tenant.with_prefix(prefix, fn ->
          Phoenix.PubSub.subscribe(Brando.pubsub(), Videos.video_topic(id))
          ProcessingStatus.subscribe(:video, id)
        end)

        send(test, {:following, prefix})
        forward(test, prefix)
      end)

    assert_receive {:following, ^prefix}
    Process.put(:followers, [pid | Process.get(:followers, [])])
  end

  defp forward(test, prefix) do
    receive do
      {video, [:video, :updated]} ->
        send(test, {:heard, prefix, :form, video})
        forward(test, prefix)

      {:asset_processing, :video, video, _state} ->
        send(test, {:heard, prefix, :processing, video})
        forward(test, prefix)

      {:settle, ref} ->
        send(test, {:settled, ref})
        forward(test, prefix)
    end
  end

  # A follower answers :settle after forwarding what came before it, so a
  # refute_received after settle/0 sees every update a follower got
  defp settle do
    for pid <- Process.get(:followers, []) do
      ref = make_ref()
      send(pid, {:settle, ref})
      assert_receive {:settled, ^ref}
    end
  end
end

defmodule Brando.Videos.VideoTopicTest do
  @moduledoc """
  A provider's update to a video reaches the admin forms that started its
  upload in the video's own environment, and no form in another environment
  that holds a video with the same id (#4010). Site Acme has a production and
  a staging environment, each in its own schema; their videos share no id
  sequence of their own, so a test gives a video in one the id of a video in
  the other.
  """
  # Synchronous: provider settings are the application's, and the
  # environments' schemas have fixed names.
  use Brando.LiveCase, async: false
  use Oban.Testing, repo: BrandoIntegration.Repo

  import ExUnit.CaptureIO

  alias Brando.SyncTest
  alias Brando.Tenant
  alias Brando.Videos
  alias Brando.Videos.Uploaders.Bunny
  alias Brando.Videos.Uploaders.Cloudflare
  alias Brando.Videos.Uploaders.Mux
  alias Brando.Videos.Uploaders.ProviderUpdate
  alias Brando.Videos.Uploaders.Vimeo
  alias Brando.Videos.Video
  alias BrandoAdmin.Components.Form.Transformer

  @production "tenant_videotopic_production"
  @staging "tenant_videotopic_staging"
  @row_clip ~s(input[name="article[items][0][clip_id]"])

  defmodule Migrator do
    @moduledoc false
    @behaviour Brando.Environments.Migrator

    @impl true
    def migrate(_site, _environment), do: {:ok, []}
  end

  test "without tenancy the topic is the one it has always been" do
    assert Videos.video_topic(42) == "brando:video:42"
  end

  describe "in an installation with environments" do
    @describetag :tmp_dir

    setup %{tmp_dir: dir, current_user: user} do
      put_test_env(:media_path, Path.join(dir, "media"))
      put_test_env(:sites_path, Path.join(dir, "sites"))
      put_test_env(:tenant_migrator, Migrator)
      put_test_env(:tenant_structure_cloner, Brando.TenantCloners)
      put_test_env(:environment_schema_cloner, Brando.TenantCloners)
      put_test_env(:tenancy_mode, :multi)
      Tenant.put_prefix(nil)
      Tenant.Cache.clear()

      on_exit(fn ->
        Tenant.put_prefix(nil)
        Tenant.Cache.clear()
      end)

      {:ok, _site} =
        Tenant.Setup.create_site(
          %{name: "Acme", key: "videotopic", languages: ["en"], default_language: "en", status: :active},
          user,
          environments: [
            %{name: "Production", key: "production", live: true, domain: "videotopic.test"},
            %{name: "Staging", key: "staging", live: false, domain: "staging.videotopic.test"}
          ]
        )

      :ok
    end

    test "the topic names the environment" do
      assert Tenant.with_prefix(@production, fn -> Videos.video_topic(42) end) ==
               "brando:video:42:tenant:" <> @production

      refute Tenant.with_prefix(@staging, fn -> Videos.video_topic(42) end) ==
               Tenant.with_prefix(@production, fn -> Videos.video_topic(42) end)
    end

    test "a Mux report on one environment's asset reaches only that environment's form" do
      production = insert(@production, mux_video("asset-a", "Production clip"))
      _staging = insert(@staging, %{mux_video("asset-b", "Staging clip") | id: production.id})
      follow(@production, production.id)
      follow(@staging, production.id)

      assert {:ok, _} = Mux.handle_webhook(%{"type" => "video.asset.errored", "data" => %{"id" => "asset-a"}})

      assert_receive {:heard, @production, %Video{title: "Production clip", status: :errored}}
      settle()
      refute_received {:heard, @staging, _video}
    end

    test "a Mux report on an asset both environments hold reaches each form with its own video" do
      production = insert(@production, mux_video("asset-shared", "Production clip"))
      _staging = insert(@staging, %{mux_video("asset-shared", "Staging clip") | id: production.id})
      follow(@production, production.id)
      follow(@staging, production.id)

      assert {:ok, _} = Mux.handle_webhook(%{"type" => "video.asset.errored", "data" => %{"id" => "asset-shared"}})

      assert_receive {:heard, @production, %Video{title: "Production clip"}}
      assert_receive {:heard, @staging, %Video{title: "Staging clip"}}
      settle()
      refute_received {:heard, _prefix, _video}
    end

    @tag :capture_log
    test "a Vimeo video given up on is reported in the environment its job was queued in" do
      put_test_env(Vimeo, access_token: "vimeo-token", req_options: [plug: {Req.Test, Vimeo}])
      Req.Test.stub(Vimeo, &Plug.Conn.send_resp(&1, 404, ""))

      staging = insert(@staging, vimeo_video("Staging clip"))
      _production = insert(@production, %{vimeo_video("Production clip") | id: staging.id})
      follow(@production, staging.id)
      follow(@staging, staging.id)

      args = %{"video_id" => staging.id, "tenant_prefix" => @staging}
      assert {:cancel, :gave_up} = in_fresh_process(fn -> perform_job(Brando.Worker.VimeoStatus, args) end)

      assert_receive {:heard, @staging, %Video{title: "Staging clip", status: :errored}}
      settle()
      refute_received {:heard, @production, _video}
    end

    test "Fetch details reports a Bunny video in the environment its job was queued in" do
      put_test_env(Bunny, api_key: "key", library_id: "133", req_options: [plug: {Req.Test, Bunny}])
      Req.Test.stub(Bunny, &Req.Test.json(&1, %{"availableResolutions" => "720p", "hasMP4Fallback" => true}))

      staging = insert(@staging, bunny_video("Staging clip"))
      _production = insert(@production, %{bunny_video("Production clip") | id: staging.id})
      follow(@production, staging.id)
      follow(@staging, staging.id)

      args = %{"video_id" => staging.id, "user_id" => staging.creator_id, "tenant_prefix" => @staging}
      assert :ok = in_fresh_process(fn -> perform_job(Brando.Worker.VideoMetadata, args) end)

      assert_receive {:heard, @staging, %Video{title: "Staging clip"}}
      settle()
      refute_received {:heard, @production, _video}
    end

    test "refreshing Bunny videos at release reports each environment's video there" do
      put_test_env(Bunny, api_key: "key", library_id: "133", req_options: [plug: {Req.Test, Bunny}])
      Req.Test.stub(Bunny, &Req.Test.json(&1, %{"availableResolutions" => "720p", "hasMP4Fallback" => true}))

      production = insert(@production, bunny_video("Production clip"))
      _staging = insert(@staging, %{bunny_video("Staging clip") | id: production.id})
      follow(@production, production.id)
      follow(@staging, production.id)

      capture_io(fn -> assert %{refreshed: 2} = Brando.Release.refresh_bunny_videos() end)

      assert_receive {:heard, @production, %Video{title: "Production clip"}}
      assert_receive {:heard, @staging, %Video{title: "Staging clip"}}
      settle()
      refute_received {:heard, _prefix, _video}
    end

    # The form completes an upload in its own LiveView process, which holds
    # its environment's prefix
    test "a completed Cloudflare upload is reported in the environment it was completed in" do
      put_test_env(Cloudflare, [])

      staging = insert(@staging, cloudflare_video("Staging clip"))
      _production = insert(@production, %{cloudflare_video("Production clip") | id: staging.id})
      follow(@production, staging.id)
      follow(@staging, staging.id)

      assert {:ok, %Video{status: :processing}} =
               Tenant.with_prefix(@staging, fn -> Videos.Uploader.complete_client_upload(staging) end)

      assert_receive {:heard, @staging, %Video{title: "Staging clip", status: :processing}}
      settle()
      refute_received {:heard, @production, _video}
    end
  end

  describe "an open form in each environment" do
    @describetag :tmp_dir

    setup %{tmp_dir: dir, conn: conn, current_user: user} do
      put_test_env(:media_path, Path.join(dir, "media"))
      put_test_env(:sites_path, Path.join(dir, "sites"))
      put_test_env(:tenant_migrator, Migrator)
      put_test_env(:tenant_structure_cloner, Brando.TenantCloners)
      put_test_env(:environment_schema_cloner, Brando.TenantCloners)
      put_test_env(:tenancy_mode, :multi)
      put_test_env(:default_video_upload_strategy, :bunny)
      put_test_env(Bunny, api_key: "key", library_id: "77", req_options: [plug: {Req.Test, Bunny}])
      Req.Test.stub(Bunny, &Req.Test.json(&1, %{"guid" => "6f2c1a3e-1111-2222-3333-444455556666"}))
      Tenant.put_prefix(nil)
      Tenant.Cache.clear()

      on_exit(fn ->
        Tenant.put_prefix(nil)
        Tenant.Cache.clear()
      end)

      {:ok, _site} =
        Tenant.Setup.create_site(
          %{name: "Acme", key: "videotopic", languages: ["en"], default_language: "en", status: :active},
          user,
          environments: [
            %{name: "Production", key: "production", live: true, domain: "videotopic.test"},
            %{name: "Staging", key: "staging", live: false, domain: "staging.videotopic.test"}
          ]
        )

      environments =
        for {key, prefix} <- [production: @production, staging: @staging], into: %{} do
          {:ok, article} =
            Tenant.with_prefix(prefix, fn ->
              SyncTest.create_article(
                %{title: "Reel", slug: "reel", language: "en", status: "published", items: [%{label: "A"}]},
                user
              )
            end)

          conn =
            conn
            |> Plug.Conn.put_session("brando_site_key", "videotopic")
            |> Plug.Conn.put_session("brando_environment_key", to_string(key))

          {prefix, %{article: article, conn: conn}}
        end

      %{environments: environments}
    end

    test "a video uploaded from a drawer hears its own updates, not another environment's", %{environments: envs} do
      forms =
        for prefix <- [@production, @staging], into: %{} do
          %{conn: conn, article: article} = envs[prefix]
          {view, _html} = live_form(conn, "/admin/articles/update/#{article.id}", "article_form")
          view |> with_target(cid_of(view, @row_clip)) |> render_click("open_video", %{})
          video_id = upload(view)
          :erlang.trace(view.pid, true, [:receive])
          {prefix, %{pid: view.pid, video_id: video_id}}
        end

      for {prefix, other} <- [{@production, @staging}, {@staging, @production}] do
        %{pid: pid, video_id: video_id} = forms[prefix]
        foreign = insert(other, %{bunny_video("Other environment's clip") | id: video_id})

        Tenant.with_prefix(other, fn -> ProviderUpdate.update_video(foreign, %{status: :ready}) end)
        own = Tenant.with_prefix(prefix, fn -> Brando.Repo.get!(Video, video_id) end)
        Tenant.with_prefix(prefix, fn -> ProviderUpdate.update_video(own, %{status: :processing}) end)

        assert_receive {:trace, ^pid, :receive, {%Video{id: ^video_id, status: :processing}, [:video, :updated]}}
        refute_received {:trace, ^pid, :receive, {%Video{title: "Other environment's clip"}, [:video, :updated]}}
      end
    end

    test "a video uploaded to a transformer shows its own updates, not another environment's", %{
      environments: envs
    } do
      forms =
        for prefix <- [@production, @staging], into: %{} do
          %{conn: conn, article: article} = envs[prefix]
          {view, _html} = live_form(conn, "/admin/showreels/update/#{article.id}", "showreel_form")
          transformer = transformer(view)
          video_id = view |> with_target(cid_of(view, "##{transformer.id}-uploader")) |> upload()
          {prefix, %{view: view, video_id: video_id}}
        end

      for {prefix, other} <- [{@production, @staging}, {@staging, @production}] do
        %{view: view, video_id: video_id} = forms[prefix]
        own = Tenant.with_prefix(prefix, fn -> Brando.Repo.get!(Video, video_id) end)

        foreign =
          insert(other, %{bunny_video("Other environment's clip") | id: video_id, config_target: own.config_target})

        Tenant.with_prefix(other, fn -> ProviderUpdate.update_video(foreign, %{status: :ready}) end)
        render(view)
        render(view)
        assert shown_clip(view, video_id) == nil

        Tenant.with_prefix(prefix, fn -> ProviderUpdate.update_video(own, %{status: :processing}) end)
        await(fn -> match?(%Video{status: :processing}, shown_clip(view, video_id)) end)
        assert shown_clip(view, video_id).title == own.title
      end
    end
  end

  # Starts a provider upload from `view` (or a component in it, `with_target/2`)
  # and returns the id of the video it created
  defp upload(view) do
    render_hook(view, "get_video_upload_url", %{
      "request_ref" => "ref-#{System.unique_integer([:positive])}",
      "filename" => "clip.mp4",
      "size" => 1_000,
      "mime_type" => "video/mp4"
    })

    assert_push_event(view, "video_upload_url_ready", %{video_id: video_id})
    video_id
  end

  defp transformer(view) do
    {:ok, components} = Phoenix.LiveView.Debug.live_components(view.pid)
    Enum.find(components, &(&1.module == Transformer)).assigns
  end

  # The video the transformer's row for `video_id` shows
  defp shown_clip(view, video_id) do
    view
    |> transformer()
    |> Map.fetch!(:items)
    |> Enum.find(&(Map.get(&1.source, :clip_id) == video_id))
    |> Map.fetch!(:assets)
    |> Map.get(:clip)
  end

  defp await(fun, tries \\ 100) do
    cond do
      fun.() -> :ok
      tries == 0 -> flunk("never came true")
      true -> Process.sleep(20) && await(fun, tries - 1)
    end
  end

  # A process following video `id` in `prefix`, as a form there does: it
  # sends the test each update it hears, with the prefix
  defp follow(prefix, id) do
    test = self()

    {:ok, pid} =
      Task.start_link(fn ->
        Tenant.with_prefix(prefix, fn -> Phoenix.PubSub.subscribe(Brando.pubsub(), Videos.video_topic(id)) end)
        send(test, {:following, prefix})
        forward(test, prefix)
      end)

    assert_receive {:following, ^prefix}
    Process.put(:followers, [pid | Process.get(:followers, [])])
  end

  defp forward(test, prefix) do
    receive do
      {video, [:video, :updated]} ->
        send(test, {:heard, prefix, video})
        forward(test, prefix)

      {:settle, ref} ->
        send(test, {:settled, ref})
        forward(test, prefix)
    end
  end

  # A broadcast has reached every follower's mailbox once it returns; a
  # follower answers :settle after forwarding what came before it, so a
  # refute_received after settle/0 sees every update a follower got
  defp settle do
    for pid <- Process.get(:followers, []) do
      ref = make_ref()
      send(pid, {:settle, ref})
      assert_receive {:settled, ^ref}
    end
  end

  # A job runs in a process of its own, with no prefix but the job's
  defp in_fresh_process(fun), do: fun |> Task.async() |> Task.await()

  defp insert(prefix, video), do: Tenant.with_prefix(prefix, fn -> Brando.Repo.insert!(video) end)

  defp mux_video(asset_id, title) do
    %Video{
      type: :mux,
      title: title,
      status: :ready,
      meta: %{"provider" => "mux", "mux" => %{"asset_id" => asset_id, "playback_id" => "pb-#{asset_id}"}}
    }
  end

  defp vimeo_video(title) do
    %Video{
      type: :vimeo_account,
      title: title,
      status: :processing,
      remote_id: "700",
      meta: %{"provider" => "vimeo", "vimeo" => %{"video_id" => "700"}}
    }
  end

  defp bunny_video(title) do
    %Video{
      type: :bunny,
      title: title,
      status: :ready,
      creator_id: Factory.insert(:random_user).id,
      meta: %{"provider" => "bunny", "bunny" => %{"video_guid" => "guid-#{System.unique_integer([:positive])}"}}
    }
  end

  defp cloudflare_video(title) do
    %Video{
      type: :cloudflare,
      title: title,
      status: :uploading,
      remote_id: "cf-uid",
      creator_id: Factory.insert(:random_user).id,
      meta: %{"provider" => "cloudflare", "cloudflare" => %{"uid" => "cf-uid"}}
    }
  end
end

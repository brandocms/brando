defmodule Brando.Videos.ProviderLibrarySharingTest do
  # Audit NV6: the provider accounts are the installation's, so in a multi-site
  # installation what one site may list, add and delete at the provider follows
  # the sites' provider library groups.
  use Brando.ConnCase, async: false

  import Brando.Test.Support, only: [put_test_env: 2]
  import ExUnit.CaptureLog
  import Plug.Conn

  alias Brando.Authorization.Migration
  alias Brando.Factory
  alias Brando.Repo
  alias Brando.Tenant
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry
  alias Brando.Videos.ProviderHoldings
  alias Brando.Videos.ProviderLibrary
  alias Brando.Videos.Uploader
  alias Brando.Videos.Uploaders.Bunny
  alias Brando.Videos.Uploaders.Cloudflare
  alias Brando.Videos.Uploaders.Mux
  alias Brando.Videos.Uploaders.Vimeo
  alias Brando.Videos.Video
  alias Ecto.Adapters.SQL

  # A repo of its own, to give the pool a short checkout deadline.
  defmodule ShortCheckoutRepo do
    use Ecto.Repo, otp_app: :brando, adapter: Ecto.Adapters.Postgres
  end

  setup do
    put_test_env(Mux, [])
    put_test_env(Bunny, [])
    put_test_env(Cloudflare, [])
    put_test_env(Vimeo, access_token: "vimeo-token", req_options: [plug: {Req.Test, Vimeo}])
    put_test_env(:tenancy_mode, :multi)
    Cache.clear()

    me = self()

    Req.Test.stub(Vimeo, fn conn ->
      send(me, {:vimeo, conn.method, conn.request_path})

      case {conn.method, conn.request_path} do
        {"GET", "/me/videos"} ->
          Req.Test.json(conn, %{"paging" => %{"next" => nil}, "data" => Enum.map(~w(1 2 3 4), &vimeo_video/1)})

        {"GET", "/videos/" <> id} ->
          Req.Test.json(conn, vimeo_video(id))

        {"DELETE", "/videos/" <> _id} ->
          send_resp(conn, 204, "")
      end
    end)

    on_exit(fn ->
      Tenant.put_prefix(nil)
      Cache.clear()
    end)

    # Alpha is in no group; Beta and Gamma share "news"; Delta is in "other".
    alpha = site("Alpha", "nv-alpha", nil)
    beta = site("Beta", "nv-beta", "news")
    gamma = site("Gamma", "nv-gamma", "news")
    delta = site("Delta", "nv-delta", "other")

    # Uploaded through Brando by one site each, and "4" by nobody.
    held = %{
      alpha: uploaded(alpha, "1"),
      gamma: uploaded(gamma, "2"),
      delta: uploaded(delta, "3")
    }

    {:ok, user: Factory.insert(:random_user), sites: %{alpha: alpha, beta: beta, gamma: gamma, delta: delta}, held: held}
  end

  describe "a site in no group" do
    test "gets no provider library, and adding is refused", %{sites: sites, user: user} do
      as_site(sites.alpha, fn ->
        assert ProviderLibrary.providers() == []
        assert {:error, {:unknown_strategy, :vimeo}} = ProviderLibrary.list(:vimeo)
        assert {:error, {:unknown_strategy, :vimeo}} = ProviderLibrary.import(:vimeo, "2", user)
        assert {:error, {:unknown_strategy, :vimeo}} = ProviderLibrary.import(:vimeo, "4", user)
        assert Repo.aggregate(Video, :count) == 1
      end)

      refute_received {:vimeo, _method, _path}
    end

    test "outside any site, nothing is offered", %{user: user} do
      assert Tenant.current_prefix() == nil
      assert ProviderLibrary.providers() == []
      assert {:error, {:unknown_strategy, :vimeo}} = ProviderLibrary.import(:vimeo, "4", user)
    end
  end

  describe "a site in a group" do
    test "lists what its group holds and what no site holds", %{sites: sites} do
      as_site(sites.beta, fn ->
        assert [%{strategy: :vimeo}] = ProviderLibrary.providers()
        assert {:ok, %{items: items}} = ProviderLibrary.list(:vimeo)
        assert Enum.map(items, & &1.remote_id) == ["2", "4"]
      end)

      as_site(sites.delta, fn ->
        assert {:ok, %{items: items}} = ProviderLibrary.list(:vimeo)
        assert items |> Enum.map(& &1.remote_id) |> Enum.sort() == ["3", "4"]
      end)
    end

    test "adds a video its group holds, and one no site holds", %{sites: sites, user: user} do
      as_site(sites.beta, fn ->
        assert {:ok, %Video{meta: %{"imported" => true}}} = ProviderLibrary.import(:vimeo, "2", user)
        assert {:ok, %Video{meta: %{"imported" => true}}} = ProviderLibrary.import(:vimeo, "4", user)
        assert Repo.aggregate(Video, :count) == 2
      end)
    end

    test "is refused another group's video or an isolated site's, by id", %{sites: sites, user: user} do
      as_site(sites.beta, fn ->
        assert {:error, :not_found} = ProviderLibrary.import(:vimeo, "1", user)
        assert {:error, :not_found} = ProviderLibrary.import(:vimeo, "3", user)
        assert Repo.aggregate(Video, :count) == 0
      end)

      as_site(sites.delta, fn ->
        assert {:error, :not_found} = ProviderLibrary.import(:vimeo, "2", user)
      end)

      # Refused before Vimeo is asked about it.
      refute_received {:vimeo, "GET", "/videos/" <> _id}
    end

    test "a video held both in and outside the group is shared", %{sites: sites, user: user} do
      as_site(sites.delta, fn -> uploaded_here("2") end)

      as_site(sites.beta, fn ->
        assert {:ok, %{items: items}} = ProviderLibrary.list(:vimeo)
        assert "2" in Enum.map(items, & &1.remote_id)
        assert {:ok, _video} = ProviderLibrary.import(:vimeo, "2", user)
      end)
    end

    test "a site that leaves the group stops sharing at once", %{sites: sites, user: user} do
      {:ok, _gamma} = Registry.put_provider_library_group(sites.gamma, "", :system)

      as_site(sites.beta, fn ->
        assert {:ok, %{items: items}} = ProviderLibrary.list(:vimeo)
        assert Enum.map(items, & &1.remote_id) == ["4"]
        assert {:error, :not_found} = ProviderLibrary.import(:vimeo, "2", user)
      end)
    end

    test "when it cannot be told who holds a video, none is listed or added", %{sites: sites, user: user} do
      broken = site("Broken", "nv-broken", "news", tables: :unreadable)
      assert broken.provider_library_group == "news"

      as_site(sites.beta, fn ->
        assert {:error, :holdings_unavailable} = ProviderLibrary.list(:vimeo)
        assert {:error, :holdings_unavailable} = ProviderLibrary.import(:vimeo, "4", user)
      end)
    end
  end

  describe "deleting at the provider" do
    test "is refused while another site holds the video", %{sites: sites, held: held, user: user} do
      as_site(sites.beta, fn -> {:ok, _added} = ProviderLibrary.import(:vimeo, "2", user) end)

      as_site(sites.gamma, fn ->
        assert Uploader.get_delete_timing(held.gamma) == :on_purge
        assert {:error, :held_by_another_site} = Uploader.delete_remote(held.gamma)
      end)

      refute_received {:vimeo, "DELETE", _path}

      # Once Beta's record is gone, Gamma's own delete reaches Vimeo.
      as_site(sites.beta, fn -> Repo.delete_all(Video) end)
      as_site(sites.gamma, fn -> assert :ok = Uploader.delete_remote(held.gamma) end)
      assert_received {:vimeo, "DELETE", "/videos/2"}
    end

    test "a soft-deleted record elsewhere still holds it", %{sites: sites, held: held} do
      as_site(sites.delta, fn ->
        "2" |> uploaded_here() |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second)) |> Repo.update!()
      end)

      as_site(sites.gamma, fn ->
        assert {:error, :held_by_another_site} = Uploader.delete_remote(held.gamma)
      end)

      refute_received {:vimeo, "DELETE", _path}
    end

    test "the site's own other environments hold it, as another site's", %{sites: sites, held: held} do
      staging = environment(sites.gamma, "staging")
      Tenant.with_prefix(Tenant.prefix(sites.gamma, staging), fn -> uploaded_here("2") end)

      as_site(sites.gamma, fn -> assert {:error, :held_by_another_environment} = Uploader.delete_remote(held.gamma) end)
      refute_received {:vimeo, "DELETE", _path}
    end

    test "is refused when it cannot be told who holds it", %{sites: sites, held: held} do
      site("Broken", "nv-broken", nil, tables: :unreadable)

      as_site(sites.alpha, fn ->
        assert {:error, :holdings_unavailable} = Uploader.delete_remote(held.alpha)
      end)

      refute_received {:vimeo, "DELETE", _path}
    end
  end

  describe "a Mux upload still waiting for its asset" do
    setup do
      put_test_env(Mux, access_token_id: "id", access_token_secret: "secret", req_options: [plug: {Req.Test, Mux}])
      me = self()

      Req.Test.stub(Mux, fn conn ->
        send(me, {:mux, conn.method, conn.request_path})

        case {conn.method, conn.request_path} do
          {"GET", "/video/v1/assets"} ->
            Req.Test.json(conn, %{"data" => [mux_asset("uploading", "up-1"), mux_asset("free", nil)]})

          {"GET", "/video/v1/assets/" <> id} ->
            Req.Test.json(conn, %{"data" => mux_asset(id, if(id == "uploading", do: "up-1"))})
        end
      end)

      :ok
    end

    test "is held by the site uploading it", %{sites: sites, user: user} do
      # Delta's upload: Mux has made the asset, and its webhook has not come.
      as_site(sites.delta, fn ->
        Repo.insert!(%Video{
          type: :mux,
          title: "Uploading",
          status: :uploading,
          meta: %{"provider" => "mux", "mux" => %{"upload_id" => "up-1"}}
        })
      end)

      as_site(sites.beta, fn ->
        assert {:ok, %{items: [item]}} = ProviderLibrary.list(:mux)
        assert item.remote_id == "free"
        refute Map.has_key?(item, :holding_keys)
        assert {:error, :not_found} = ProviderLibrary.import(:mux, "uploading", user)
        assert Repo.aggregate(Video, :count) == 0
      end)

      as_site(sites.delta, fn ->
        assert {:ok, %{items: items}} = ProviderLibrary.list(:mux)
        assert Enum.map(items, & &1.remote_id) == ["uploading", "free"]
        assert {:ok, %Video{meta: %{"imported" => true}}} = ProviderLibrary.import(:mux, "free", user)
      end)
    end

    test "is the site's own record, listed and added as that", %{sites: sites, user: user} do
      upload =
        as_site(sites.delta, fn ->
          Repo.insert!(%Video{
            type: :mux,
            title: "Uploading",
            status: :uploading,
            meta: %{"provider" => "mux", "mux" => %{"upload_id" => "up-1"}}
          })
        end)

      for mode <- [:multi, :single] do
        put_test_env(:tenancy_mode, mode)

        as_site(sites.delta, fn ->
          assert {:ok, %{items: items}} = ProviderLibrary.list(:mux)
          assert %{"uploading" => upload.id, "free" => nil} == Map.new(items, &{&1.remote_id, &1.video_id})

          count = Repo.aggregate(Video, :count)
          assert {:ok, %Video{id: id}} = ProviderLibrary.import(:mux, "uploading", user)
          assert id == upload.id
          assert Repo.aggregate(Video, :count) == count
        end)
      end
    end

    test "a site's own asset is added without asking Mux about it", %{sites: sites, user: user} do
      as_site(sites.beta, fn ->
        assert {:ok, %Video{id: id}} = ProviderLibrary.import(:mux, "free", user)
        assert_received {:mux, "GET", "/video/v1/assets/free"}
        flush_mux()

        assert {:ok, %Video{id: ^id}} = ProviderLibrary.import(:mux, "free", user)
        refute_received {:mux, _method, _path}
      end)
    end
  end

  describe "a delete and an add of one video" do
    setup :start_lock_conn

    test "a delete waits while the video is being added", %{sites: sites, held: held, lock_conn: conn} do
      hold_lock(conn, "vimeo.video_id", "2")
      task = Task.async(fn -> as_site(sites.gamma, fn -> Uploader.delete_remote(held.gamma) end) end)

      refute_receive {:vimeo, "DELETE", _path}, 300
      release_lock(conn, "vimeo.video_id", "2")

      assert Task.await(task) == :ok
      assert_received {:vimeo, "DELETE", "/videos/2"}
    end

    test "an add waits while the video is being deleted", %{sites: sites, user: user, lock_conn: conn} do
      hold_lock(conn, "vimeo.video_id", "4")
      task = Task.async(fn -> as_site(sites.beta, fn -> ProviderLibrary.import(:vimeo, "4", user) end) end)

      refute_receive {:vimeo, "GET", "/videos/4"}, 300
      release_lock(conn, "vimeo.video_id", "4")

      assert {:ok, %Video{}} = Task.await(task)
      assert_received {:vimeo, "GET", "/videos/4"}
    end

    test "the provider is asked outside a transaction, and the lock ends with the call",
         %{sites: sites, held: held, user: user, lock_conn: conn} do
      me = self()

      Req.Test.stub(Vimeo, fn conn ->
        send(me, {:in_transaction?, conn.method, Repo.repo().in_transaction?()})

        case conn.method do
          "GET" -> Req.Test.json(conn, vimeo_video(Path.basename(conn.request_path)))
          "DELETE" -> send_resp(conn, 204, "")
        end
      end)

      as_site(sites.beta, fn -> assert {:ok, %Video{}} = ProviderLibrary.import(:vimeo, "4", user) end)
      assert_received {:in_transaction?, "GET", false}
      assert lock_free?(conn, "vimeo.video_id", "4")

      as_site(sites.alpha, fn -> assert :ok = Uploader.delete_remote(held.alpha) end)
      assert_received {:in_transaction?, "DELETE", false}
      assert lock_free?(conn, "vimeo.video_id", "1")
    end

    test "inside the caller's transaction, the lock lasts until that ends", %{sites: sites, held: held, lock_conn: conn} do
      as_site(sites.alpha, fn ->
        Repo.transaction(fn ->
          assert :ok = Uploader.delete_remote(held.alpha)
          refute lock_free?(conn, "vimeo.video_id", "1")
        end)
      end)
    end

    test "a lock held too long is an error, and the delete is kept for the next purge",
         %{sites: sites, held: held, user: user, lock_conn: conn} do
      put_test_env(Brando.Videos.ProviderHoldings, lock_timeout: 200)
      hold_lock(conn, "vimeo.video_id", "4")
      hold_lock(conn, "vimeo.video_id", "1")

      as_site(sites.beta, fn -> assert {:error, :busy} = ProviderLibrary.import(:vimeo, "4", user) end)
      as_site(sites.alpha, fn -> assert {:error, :busy} = Uploader.delete_remote(held.alpha) end)

      as_site(sites.alpha, fn ->
        expire(held.alpha)
        Brando.SoftDelete.Query.clean_up_soft_deletions()
        assert Repo.aggregate(Video, :count) == 1
      end)

      refute_received {:vimeo, "GET", "/videos/4"}
      refute_received {:vimeo, "DELETE", _path}

      release_lock(conn, "vimeo.video_id", "1")

      as_site(sites.alpha, fn ->
        Brando.SoftDelete.Query.clean_up_soft_deletions()
        assert Repo.aggregate(Video, :count) == 0
      end)

      assert_received {:vimeo, "DELETE", "/videos/1"}
    end

    # A pool drops a checkout that outlasts its deadline (15 s by default, the
    # repo's `:timeout`) and closes its connection, which ends the session's
    # lock. Here the deadline is 200 ms.
    test "the lock is held for as long as the call takes, past the pool's checkout deadline", %{lock_conn: conn} do
      use_short_checkout_repo()

      assert ProviderHoldings.with_video_lock("vimeo.video_id", "slow", fn ->
               Process.sleep(500)
               lock_free?(conn, "vimeo.video_id", "slow")
             end) == false

      assert lock_free?(conn, "vimeo.video_id", "slow")
    end

    test "a wait past the pool's checkout deadline is still :busy", %{lock_conn: conn} do
      use_short_checkout_repo()
      put_test_env(Brando.Videos.ProviderHoldings, lock_timeout: 500)
      hold_lock(conn, "vimeo.video_id", "slow")

      assert {:error, :busy} = ProviderHoldings.with_video_lock("vimeo.video_id", "slow", fn -> :ran end)
    end
  end

  describe "a delete with delete_remote_on: :on_delete" do
    setup :start_lock_conn

    setup do
      put_test_env(Vimeo,
        access_token: "vimeo-token",
        delete_remote_on: :on_delete,
        req_options: [plug: {Req.Test, Vimeo}]
      )

      me = self()

      Req.Test.stub(Vimeo, fn conn ->
        send(me, {:vimeo_delete, conn.request_path, Repo.repo().in_transaction?(), Tenant.current_prefix()})
        send_resp(conn, 204, "")
      end)

      :ok
    end

    for authorization_mode <- [:legacy, :groups], tenancy_mode <- [:none, :multi] do
      @authorization_mode authorization_mode
      @tenancy_mode tenancy_mode

      test "asks the provider once it has committed, #{authorization_mode} authorization, #{tenancy_mode} tenancy",
           %{sites: sites, held: held} do
        put_test_env(:tenancy_mode, @tenancy_mode)
        superuser = superuser(@authorization_mode)

        {video, prefix} =
          case @tenancy_mode do
            :none -> {uploaded_here("5"), nil}
            :multi -> {held.alpha, site_prefix(sites.alpha)}
          end

        in_prefix(prefix, fn -> assert {:ok, _video} = Brando.Videos.delete_video(video.id, superuser) end)

        path = "/videos/#{video.remote_id}"
        assert_received {:vimeo_delete, ^path, false, ^prefix}
      end
    end

    test "a delete rolled back is not made at the provider", %{sites: sites, held: held} do
      superuser = superuser(:groups)

      as_site(sites.alpha, fn ->
        assert {:error, :undone} =
                 Repo.transaction(fn ->
                   {:ok, _video} = Brando.Videos.delete_video(held.alpha.id, superuser)
                   Repo.rollback(:undone)
                 end)
      end)

      refute_received {:vimeo_delete, _path, _in_transaction?, _prefix}
    end

    test "a video left at the provider is logged", %{sites: sites, held: held, lock_conn: conn} do
      put_test_env(Brando.Videos.ProviderHoldings, lock_timeout: 200)
      hold_lock(conn, "vimeo.video_id", "1")
      Logger.put_module_level(Brando.Videos, :warning)
      on_exit(fn -> Logger.delete_module_level(Brando.Videos) end)

      log =
        capture_log([level: :warning], fn ->
          as_site(sites.alpha, fn -> assert {:ok, _video} = Brando.Videos.delete_video(held.alpha.id, :system) end)
        end)

      refute_received {:vimeo_delete, _path, _in_transaction?, _prefix}
      assert log =~ "Video #{held.alpha.id}"
      assert log =~ "busy"
    end
  end

  describe "an environment being created or copied" do
    test "holds nothing until its schema is there", %{sites: sites, held: held, user: user} do
      pending = site("Pending", "nv-pending", "news", schema: false)
      environment(pending, "staging", tables: false)

      as_site(sites.beta, fn ->
        assert {:ok, %{items: items}} = ProviderLibrary.list(:vimeo)
        assert Enum.map(items, & &1.remote_id) == ["2", "4"]
        assert {:ok, _video} = ProviderLibrary.import(:vimeo, "4", user)
      end)

      as_site(sites.alpha, fn -> assert :ok = Uploader.delete_remote(held.alpha) end)
      assert_received {:vimeo, "DELETE", "/videos/1"}
    end

    test "an unreadable holding leaves the editor's transaction usable", %{sites: sites, held: held} do
      site("Broken", "nv-broken", nil, tables: :unreadable)

      as_site(sites.alpha, fn ->
        assert {:ok, 1} =
                 Repo.transaction(fn ->
                   assert {:error, :holdings_unavailable} = Uploader.delete_remote(held.alpha)
                   Repo.aggregate(Video, :count)
                 end)
      end)
    end
  end

  describe "purging soft-deleted videos" do
    test "keeps a video whose holders cannot be told, for the next run", %{sites: sites, held: held} do
      broken = site("Broken", "nv-broken", nil, tables: :unreadable)
      as_site(sites.alpha, fn -> expire(held.alpha) end)

      as_site(sites.alpha, fn ->
        Brando.SoftDelete.Query.clean_up_soft_deletions()
        assert Repo.aggregate(Video, :count) == 1
      end)

      refute_received {:vimeo, "DELETE", _path}

      [environment] = broken.environments
      SQL.query!(Repo.repo(), ~s(DROP TABLE "#{Tenant.prefix(broken, environment)}"."videos"))

      as_site(sites.alpha, fn ->
        Brando.SoftDelete.Query.clean_up_soft_deletions()
        assert Repo.aggregate(Video, :count) == 0
      end)

      assert_received {:vimeo, "DELETE", "/videos/1"}
    end

    test "deletes a video another site holds, and leaves it at the provider", %{sites: sites, held: held, user: user} do
      as_site(sites.beta, fn -> {:ok, _added} = ProviderLibrary.import(:vimeo, "2", user) end)
      as_site(sites.gamma, fn -> expire(held.gamma) end)

      as_site(sites.gamma, fn ->
        Brando.SoftDelete.Query.clean_up_soft_deletions()
        assert Repo.aggregate(Video, :count) == 0
      end)

      refute_received {:vimeo, "DELETE", _path}
    end
  end

  # #3420: an environment copied from another has the same remote videos, so
  # one environment's delete must not take the video from the others.
  describe "a site's named environments" do
    setup %{sites: sites} do
      put_test_env(Mux, access_token_id: "id", access_token_secret: "secret", req_options: [plug: {Req.Test, Mux}])
      # With `:single` tenancy, alpha is the installation's site.
      put_test_env(:site_key, sites.alpha.key)
      Logger.put_module_level(Uploader, :info)
      on_exit(fn -> Logger.delete_module_level(Uploader) end)
      me = self()

      Req.Test.stub(Mux, fn conn ->
        send(me, {:mux, conn.method, conn.request_path, Tenant.current_prefix()})
        send_resp(conn, 204, "")
      end)

      # Production uploaded the asset, and staging was copied from it.
      staging = environment(sites.alpha, "staging")
      production_prefix = site_prefix(sites.alpha)
      staging_prefix = Tenant.prefix(sites.alpha, staging)

      {:ok,
       production: Tenant.with_prefix(production_prefix, fn -> mux_uploaded_here("asset-1") end),
       staging: Tenant.with_prefix(staging_prefix, fn -> mux_uploaded_here("asset-1") end),
       production_prefix: production_prefix,
       staging_prefix: staging_prefix}
    end

    for tenancy_mode <- [:single, :multi] do
      @tenancy_mode tenancy_mode

      test "a purge in staging leaves production's video at the provider, #{tenancy_mode} tenancy", context do
        put_test_env(:tenancy_mode, @tenancy_mode)
        Tenant.with_prefix(context.staging_prefix, fn -> expire(context.staging) end)

        log =
          capture_log([level: :info], fn ->
            Tenant.with_prefix(context.staging_prefix, fn ->
              Brando.SoftDelete.Query.clean_up_soft_deletions()
              assert Repo.aggregate(Video, :count) == 0
            end)
          end)

        refute_received {:mux, "DELETE", _path, _prefix}
        assert log =~ "Video #{context.staging.id} left at its provider: held_by_another_environment"
        assert log =~ context.production_prefix

        # Production still plays it, and once it is the last holder its own
        # purge deletes the asset at Mux.
        Tenant.with_prefix(context.production_prefix, fn ->
          assert Repo.get!(Video, context.production.id).deleted_at == nil
          expire(context.production)
          Brando.SoftDelete.Query.clean_up_soft_deletions()
          refute Repo.get(Video, context.production.id)
        end)

        production_prefix = context.production_prefix
        assert_received {:mux, "DELETE", "/video/v1/assets/asset-1", ^production_prefix}
      end
    end

    for authorization_mode <- [:legacy, :groups] do
      @authorization_mode authorization_mode

      test "with delete_remote_on: :on_delete, only the last holder's delete reaches the provider, " <>
             "#{authorization_mode} authorization",
           context do
        put_test_env(:tenancy_mode, :single)

        put_test_env(Mux,
          access_token_id: "id",
          access_token_secret: "secret",
          delete_remote_on: :on_delete,
          req_options: [plug: {Req.Test, Mux}]
        )

        superuser = superuser(@authorization_mode)

        Tenant.with_prefix(context.staging_prefix, fn ->
          assert {:ok, _video} = Brando.Videos.delete_video(context.staging.id, superuser)
        end)

        refute_received {:mux, "DELETE", _path, _prefix}

        # Staging's record is soft-deleted, and its purge will not ask the
        # provider, so it no longer holds the video from production.
        Tenant.with_prefix(context.staging_prefix, fn ->
          assert Repo.get!(Video, context.staging.id).deleted_at
        end)

        Tenant.with_prefix(context.production_prefix, fn ->
          assert {:ok, _video} = Brando.Videos.delete_video(context.production.id, superuser)
        end)

        production_prefix = context.production_prefix
        assert_received {:mux, "DELETE", "/video/v1/assets/asset-1", ^production_prefix}
      end
    end

    test "with delete_remote_on: :on_purge, a soft-deleted record in another environment still holds it", context do
      put_test_env(:tenancy_mode, :single)

      Tenant.with_prefix(context.staging_prefix, fn ->
        context.staging |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second)) |> Repo.update!()
      end)

      Tenant.with_prefix(context.production_prefix, fn ->
        assert {:error, :held_by_another_environment} = Uploader.delete_remote(context.production)
      end)

      refute_received {:mux, "DELETE", _path, _prefix}
    end

    test "with delete_remote_on: :on_delete, another site's soft-deleted record still holds it", context do
      put_test_env(:tenancy_mode, :multi)

      put_test_env(Mux,
        access_token_id: "id",
        access_token_secret: "secret",
        delete_remote_on: :on_delete,
        req_options: [plug: {Req.Test, Mux}]
      )

      Tenant.with_prefix(context.staging_prefix, fn -> Repo.delete_all(Video) end)

      as_site(context.sites.gamma, fn ->
        "asset-1" |> mux_uploaded_here() |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second)) |> Repo.update!()
      end)

      Tenant.with_prefix(context.production_prefix, fn ->
        assert {:error, :held_by_another_site} = Uploader.delete_remote(context.production)
      end)

      refute_received {:mux, "DELETE", _path, _prefix}
    end

    # Two purges of one video, in two environments, must not both read the
    # other's row and both leave the video at the provider: the row is purged
    # before the lock is given back, so the next purge does not see it.
    for tenancy_mode <- [:single, :multi] do
      @tenancy_mode tenancy_mode

      test "a purge deletes its row while it holds the video's lock, #{tenancy_mode} tenancy", context do
        put_test_env(:tenancy_mode, @tenancy_mode)
        {:ok, lock_conn: conn} = start_lock_conn(context)
        Tenant.with_prefix(context.staging_prefix, fn -> expire(context.staging) end)

        me = self()
        staging_id = context.staging.id
        handler = {__MODULE__, :purge_lock, make_ref()}

        :telemetry.attach(
          handler,
          Repo.repo().config()[:telemetry_prefix] ++ [:query],
          fn _event, _measurements, metadata, _config ->
            # Staging's row, by its id.
            if metadata.source == "videos" and String.starts_with?(metadata.query, "DELETE") and
                 staging_id in List.flatten(metadata.params),
               do: send(me, {:staging_row_deleted, lock_free?(conn, "mux.asset_id", "asset-1")})
          end,
          nil
        )

        on_exit(fn -> :telemetry.detach(handler) end)

        Tenant.with_prefix(context.staging_prefix, fn ->
          Brando.SoftDelete.Query.clean_up_soft_deletions()
          assert Repo.aggregate(Video, :count) == 0
        end)

        assert_received {:staging_row_deleted, false}
        refute_received {:mux, "DELETE", _path, _prefix}
        assert lock_free?(conn, "mux.asset_id", "asset-1")
      end
    end

    test "another site's environments do not count as the site's own", context do
      gamma_prefix = site_prefix(context.sites.gamma)
      gamma = Tenant.with_prefix(gamma_prefix, fn -> mux_uploaded_here("asset-2") end)

      for mode <- [:single, :multi] do
        put_test_env(:tenancy_mode, mode)

        # Alpha's two environments hold asset-1, not gamma's asset-2.
        Tenant.with_prefix(gamma_prefix, fn -> assert :ok = Uploader.delete_remote(gamma) end)
        assert_received {:mux, "DELETE", "/video/v1/assets/asset-2", ^gamma_prefix}

        # Alpha's staging is alpha's own, not another site.
        Tenant.with_prefix(context.production_prefix, fn ->
          assert {:error, :held_by_another_environment} = Uploader.delete_remote(context.production)
        end)

        refute_received {:mux, "DELETE", "/video/v1/assets/asset-1", _prefix}
      end

      # With one site, alpha's staging does not hold gamma's video, nor gamma
      # alpha's: only the deleting site's environments are read.
      put_test_env(:tenancy_mode, :single)
      Tenant.with_prefix(gamma_prefix, fn -> mux_uploaded_here("asset-3") end)
      alpha = Tenant.with_prefix(context.production_prefix, fn -> mux_uploaded_here("asset-3") end)

      Tenant.with_prefix(context.production_prefix, fn -> assert :ok = Uploader.delete_remote(alpha) end)
      assert_received {:mux, "DELETE", "/video/v1/assets/asset-3", _prefix}
    end

    test "held by another site and by another environment of its own, another site's holding is told", context do
      put_test_env(:tenancy_mode, :multi)
      as_site(context.sites.gamma, fn -> mux_uploaded_here("asset-1") end)

      log =
        capture_log([level: :info], fn ->
          Tenant.with_prefix(context.production_prefix, fn ->
            assert {:error, :held_by_another_site} = Uploader.delete_remote(context.production)
          end)
        end)

      assert log =~ "Video #{context.production.id} left at its provider: held_by_another_site"
      refute_received {:mux, "DELETE", _path, _prefix}
    end

    test "an archive does not hold it", context do
      archive = context.production_prefix <> "_archive_20260101000000"
      SQL.query!(Repo.repo(), ~s(CREATE SCHEMA "#{archive}"))
      Enum.each(content_tables(), &clone_table(archive, &1))
      video = Tenant.with_prefix(context.production_prefix, fn -> mux_uploaded_here("asset-2") end)

      SQL.query!(
        Repo.repo(),
        ~s(INSERT INTO "#{archive}"."videos" SELECT * FROM "#{context.production_prefix}"."videos" WHERE id = $1),
        [video.id]
      )

      put_test_env(:tenancy_mode, :single)
      Tenant.with_prefix(context.production_prefix, fn -> assert :ok = Uploader.delete_remote(video) end)
      assert_received {:mux, "DELETE", "/video/v1/assets/asset-2", _prefix}
    end

    test "is refused when one of the site's environments cannot be read", context do
      put_test_env(:tenancy_mode, :single)
      environment(context.sites.alpha, "broken", tables: :unreadable)
      Tenant.with_prefix(context.staging_prefix, fn -> expire(context.staging) end)

      Tenant.with_prefix(context.staging_prefix, fn ->
        assert {:error, :holdings_unavailable} = Uploader.delete_remote(context.staging)
        Brando.SoftDelete.Query.clean_up_soft_deletions()
        assert Repo.aggregate(Video, :count) == 1
      end)

      refute_received {:mux, "DELETE", _path, _prefix}
    end

    test "without named environments, deletes as before" do
      put_test_env(:tenancy_mode, :none)
      video = mux_uploaded_here("asset-1")

      assert :ok = Uploader.delete_remote(video)
      assert_received {:mux, "DELETE", "/video/v1/assets/asset-1", nil}
    end
  end

  describe "single-site installations" do
    test "list and add the whole account, and delete as before", %{sites: sites, held: held, user: user} do
      for mode <- [:single, :none] do
        put_test_env(:tenancy_mode, mode)

        as_site(sites.alpha, fn ->
          assert [%{strategy: :vimeo}] = ProviderLibrary.providers()
          assert {:ok, %{items: items}} = ProviderLibrary.list(:vimeo)
          assert Enum.map(items, & &1.remote_id) == ~w(1 2 3 4)
          assert {:ok, %Video{}} = ProviderLibrary.import(:vimeo, "3", user)
          # Another site's record does not count without several sites.
          assert :ok = Uploader.delete_remote(held.gamma)
        end)

        assert_received {:vimeo, "DELETE", "/videos/2"}
      end
    end
  end

  describe "choosing a site's group" do
    test "only an installation superuser may, in legacy mode", %{sites: sites} do
      for role <- [:admin, :editor, :user] do
        assert {:error, changeset} =
                 Registry.put_provider_library_group(sites.alpha, "news", Factory.insert(:random_user, role: role))

        assert [provider_library_group: _message] = changeset.errors
      end

      assert {:error, _changeset} = Registry.put_provider_library_group(sites.alpha, "news", nil)
      assert Registry.get_site(sites.alpha.id).provider_library_group == nil

      superuser = Factory.insert(:random_user, role: :superuser)

      assert {:ok, %{provider_library_group: "news"}} =
               Registry.put_provider_library_group(sites.alpha, " news ", superuser)

      assert {:ok, %{provider_library_group: nil}} = Registry.put_provider_library_group(sites.alpha, "", superuser)

      assert {:error, changeset} = Registry.put_provider_library_group(sites.alpha, "News Room", superuser)
      assert [provider_library_group: _format] = changeset.errors
    end

    test "in groups mode, the Superuser group decides", %{sites: sites} do
      put_test_env(:authorization_mode, :groups)
      owner = Factory.insert(:random_user, role: :superuser)
      {:ok, _} = Migration.run()

      # Holds the legacy role, but is in no Superuser group.
      assert {:error, _changeset} =
               Registry.put_provider_library_group(sites.alpha, "news", Factory.insert(:random_user, role: :superuser))

      assert {:ok, %{provider_library_group: "news"}} = Registry.put_provider_library_group(sites.alpha, "news", owner)
    end

    test "its errors are in the editor's language", %{sites: sites} do
      superuser = Factory.insert(:random_user, role: :superuser)

      # A malformed key, and one too long.
      for group <- ["News Room", String.duplicate("a", 41)] do
        [en, no] =
          for locale <- ["en", "no"] do
            Gettext.with_locale(Brando.Gettext, locale, fn ->
              {:error, changeset} = Registry.put_provider_library_group(sites.alpha, group, superuser)
              assert [provider_library_group: {message, _opts}] = changeset.errors
              message
            end)
          end

        refute en == no
        refute en =~ "%{"
      end
    end

    test "an ordinary site update does not change it", %{sites: sites} do
      assert {:ok, site} = Registry.update_site(sites.beta, %{provider_library_group: nil, name: "Beta renamed"})
      assert site.provider_library_group == "news"
    end
  end

  defp site(name, key, group, opts \\ []) do
    {:ok, site} =
      Registry.create_site(%{
        name: name,
        key: key,
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :dynamic
      })

    {:ok, site} = Registry.put_provider_library_group(site, group, :system)
    environment(site, "production", opts)
    Registry.get_site(site.id)
  end

  # The content tables' structure, as an environment has them. With
  # `tables: false`, a schema with none, as while an environment is created
  # or copied; with `schema: false`, no schema at all. With
  # `tables: :unreadable`, a `videos` table the holdings cannot read.
  defp environment(site, key, opts \\ []) do
    {:ok, environment} = Registry.create_environment(site, %{name: key, key: key, live: key == "production"})
    prefix = Tenant.prefix(site, environment)

    if Keyword.get(opts, :schema, true) do
      SQL.query!(Repo.repo(), ~s(CREATE SCHEMA "#{prefix}"))

      case Keyword.get(opts, :tables, true) do
        true -> Enum.each(content_tables(), &clone_table(prefix, &1))
        false -> :ok
        :unreadable -> SQL.query!(Repo.repo(), ~s|CREATE TABLE "#{prefix}"."videos" (id bigint)|)
      end
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

  defp as_site(site, fun) do
    Tenant.with_prefix(site_prefix(site), fun)
  end

  defp site_prefix(site) do
    site = Registry.get_site(site.id)
    environment = Enum.find(site.environments, & &1.live)
    Tenant.prefix(site, environment)
  end

  defp in_prefix(nil, fun), do: fun.()
  defp in_prefix(prefix, fun), do: Tenant.with_prefix(prefix, fun)

  defp superuser(:legacy), do: Factory.insert(:random_user, role: :superuser)

  defp superuser(:groups) do
    put_test_env(:authorization_mode, :groups)
    superuser = Factory.insert(:random_user, role: :superuser)
    {:ok, _} = Migration.run()
    superuser
  end

  defp uploaded(site, remote_id), do: as_site(site, fn -> uploaded_here(remote_id) end)

  defp uploaded_here(remote_id) do
    Repo.insert!(%Video{
      type: :vimeo_account,
      title: "Video #{remote_id}",
      remote_id: remote_id,
      status: :ready,
      meta: %{"provider" => "vimeo", "vimeo" => %{"video_id" => remote_id}}
    })
  end

  defp mux_uploaded_here(asset_id) do
    Repo.insert!(%Video{
      type: :mux,
      title: "Asset #{asset_id}",
      status: :ready,
      meta: %{"provider" => "mux", "mux" => %{"asset_id" => asset_id, "playback_id" => "pb-#{asset_id}"}}
    })
  end

  defp expire(video) do
    video |> Ecto.Changeset.change(deleted_at: DateTime.add(DateTime.utc_now(:second), -31, :day)) |> Repo.update!()
  end

  # A session of its own, outside the sandbox, to hold and test locks with.
  defp start_lock_conn(_context) do
    {:ok, conn} = Postgrex.start_link(Keyword.drop(Repo.repo().config(), [:pool, :ownership_pool, :pool_size, :name]))
    {:ok, lock_conn: conn}
  end

  # Another session holds the video's lock, as a delete or an add in progress.
  defp hold_lock(conn, path, remote_id) do
    Postgrex.query!(conn, "SELECT pg_advisory_lock(hashtextextended($1, 0))", [lock_key(path, remote_id)])
  end

  defp release_lock(conn, path, remote_id) do
    Postgrex.query!(conn, "SELECT pg_advisory_unlock(hashtextextended($1, 0))", [lock_key(path, remote_id)])
  end

  # Takes the lock and gives it back at once, if no other session holds it.
  defp lock_free?(conn, path, remote_id) do
    case Postgrex.query!(conn, "SELECT pg_try_advisory_lock(hashtextextended($1, 0))", [lock_key(path, remote_id)]) do
      %{rows: [[true]]} ->
        release_lock(conn, path, remote_id)
        true

      %{rows: [[false]]} ->
        false
    end
  end

  defp use_short_checkout_repo do
    config = Keyword.drop(Repo.repo().config(), [:pool, :ownership_pool, :pool_size, :name])
    start_supervised!({ShortCheckoutRepo, Keyword.merge(config, pool_size: 2, timeout: 200)})
    put_test_env(:repo_module, ShortCheckoutRepo)
  end

  defp lock_key(path, remote_id), do: "brando:provider_video:#{path}:#{remote_id}"

  defp flush_mux do
    receive do
      {:mux, _method, _path} -> flush_mux()
    after
      0 -> :ok
    end
  end

  defp mux_asset(id, upload_id) do
    Map.reject(
      %{
        "id" => id,
        "status" => "ready",
        "upload_id" => upload_id,
        "passthrough" => "Asset #{id}",
        "playback_ids" => [%{"id" => "pb-#{id}", "policy" => "public"}],
        "tracks" => []
      },
      fn {_key, value} -> is_nil(value) end
    )
  end

  defp vimeo_video(id) do
    %{
      "uri" => "/videos/#{id}",
      "name" => "Video #{id}",
      "link" => "https://vimeo.com/#{id}",
      "status" => "available",
      "transcode" => %{"status" => "complete"},
      "width" => 1280,
      "height" => 720,
      "duration" => 30,
      "created_time" => "2026-09-01T10:00:00+00:00",
      "files" => [%{"quality" => "hls", "link" => "https://player.vimeo.com/external/#{id}.m3u8?s=x"}]
    }
  end
end

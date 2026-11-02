defmodule Brando.Videos.ProviderVideoReaddTest do
  # #3436: a video deleted in Brando and added again from the provider's
  # library, in the same environment, before the deleted record is purged.
  # The purge must not delete at the provider the video the added record plays.
  use Brando.ConnCase, async: false

  import Brando.Test.Support, only: [put_test_env: 2]
  import Ecto.Query, only: [from: 2]
  import Plug.Conn

  alias Brando.Authorization.Groups
  alias Brando.Authorization.Migration
  alias Brando.Authorization.Scope
  alias Brando.Factory
  alias Brando.Repo
  alias Brando.Videos.ProviderLibrary
  alias Brando.Videos.Uploaders.Mux
  alias Brando.Videos.Video

  setup do
    put_test_env(:tenancy_mode, :none)
    mux(:on_purge)
    me = self()

    Req.Test.stub(Mux, fn conn ->
      send(me, {:mux, conn.method, conn.request_path})

      case conn.method do
        "GET" -> Req.Test.json(conn, %{"data" => mux_asset("asset-1")})
        "DELETE" -> send_resp(conn, 204, "")
      end
    end)

    :ok
  end

  for authorization_mode <- [:legacy, :groups] do
    @authorization_mode authorization_mode

    test "a video deleted and added again is not deleted at the provider by the purge, " <>
           "#{authorization_mode} authorization" do
      user = superuser(@authorization_mode)
      uploaded = mux_uploaded("asset-1")

      assert {:ok, _deleted} = Brando.Videos.delete_video(uploaded.id, user)
      assert {:ok, added} = ProviderLibrary.import(:mux, "asset-1", user)

      expire_deleted()
      Brando.SoftDelete.Query.clean_up_soft_deletions()

      refute_received {:mux, "DELETE", _path}
      assert_plays(added)

      # The one record of the video: the deleted one, back in the library.
      assert added.id == uploaded.id
      assert Repo.aggregate(Video, :count) == 1
    end
  end

  test "with delete_remote_on: :on_delete, the video left at the provider is added as a new record" do
    mux(:on_delete)
    user = superuser(:legacy)
    uploaded = mux_uploaded("asset-1")

    me = self()

    # The provider refused the delete, so the video is still there.
    Req.Test.stub(Mux, fn conn ->
      send(me, {:mux, conn.method, conn.request_path})

      case conn.method do
        "GET" -> Req.Test.json(conn, %{"data" => mux_asset("asset-1")})
        "DELETE" -> send_resp(conn, 500, "")
      end
    end)

    assert {:ok, _deleted} = Brando.Videos.delete_video(uploaded.id, user)

    # The deleted record's video may be gone at the provider, which its
    # delete asked: the add asks the provider and makes a record of its own.
    assert {:ok, added} = ProviderLibrary.import(:mux, "asset-1", user)
    assert added.id != uploaded.id
    assert ProviderLibrary.imported?(added)

    expire_deleted()
    Brando.SoftDelete.Query.clean_up_soft_deletions()

    assert Repo.aggregate(Video, :count) == 1
    assert_plays(added)
  end

  test "a live record of the video in the environment keeps it at the provider when another is purged" do
    # Two records of one video, as an add made before #3436 left them.
    uploaded = mux_uploaded("asset-1")
    imported = mux_uploaded("asset-1", imported: true)
    expire(uploaded)

    Brando.SoftDelete.Query.clean_up_soft_deletions()

    refute_received {:mux, "DELETE", _path}
    refute Repo.get(Video, uploaded.id)
    assert_plays(imported)

    # The last record's purge deletes it at the provider.
    other = mux_uploaded("asset-2")
    expire(other)
    Brando.SoftDelete.Query.clean_up_soft_deletions()
    assert_received {:mux, "DELETE", "/video/v1/assets/asset-2"}
  end

  test "a record restored after the purge read it is not purged, nor its video deleted" do
    uploaded = "asset-1" |> mux_uploaded() |> expire()

    # The purge reads the expired records, then a restore lands before it
    # asks the provider.
    restore_after_purge_reads(uploaded)
    Brando.SoftDelete.Query.clean_up_soft_deletions()

    refute_received {:mux, "DELETE", _path}
    assert_plays(Repo.get!(Video, uploaded.id))
  end

  test "a user who may not restore the deleted record adds the video as a new record" do
    put_test_env(:authorization_mode, :groups)
    owner = Factory.insert(:random_user, role: :superuser)
    user = Factory.insert(:random_user, role: :user)
    {:ok, _} = Migration.run()

    {:ok, group} =
      Groups.create(
        Scope.standalone(owner),
        %{name: "Adds videos"},
        ~w(brando.admin.access brando.videos.read brando.videos.create)
      )

    {:ok, :ok} = Groups.add_member(Scope.standalone(owner), group.id, user.id)

    uploaded = mux_uploaded("asset-1")
    uploaded |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second)) |> Repo.update!()

    assert {:ok, added} = ProviderLibrary.import(:mux, "asset-1", user)
    assert added.id != uploaded.id
    assert Repo.get!(Video, uploaded.id).deleted_at

    expire_deleted()
    Brando.SoftDelete.Query.clean_up_soft_deletions()

    refute_received {:mux, "DELETE", _path}
    assert_plays(added)
  end

  describe "an add and a purge of one video" do
    setup do
      {:ok, conn} = Postgrex.start_link(Keyword.drop(Repo.repo().config(), [:pool, :ownership_pool, :pool_size, :name]))
      {:ok, lock_conn: conn}
    end

    test "an add waits while the video is being purged", %{lock_conn: conn} do
      user = superuser(:legacy)
      lock(conn, "pg_advisory_lock")
      task = Task.async(fn -> ProviderLibrary.import(:mux, "asset-1", user) end)

      # Mux is asked which upload the asset came from before the lock, and
      # for the asset to add once it has it.
      assert_receive {:mux, "GET", "/video/v1/assets/asset-1"}
      refute_receive {:mux, "GET", "/video/v1/assets/asset-1"}, 300
      lock(conn, "pg_advisory_unlock")

      assert {:ok, %Video{}} = Task.await(task)
    end

    test "a purge waits while the video is being added", %{lock_conn: conn} do
      uploaded = mux_uploaded("asset-1")
      expire(uploaded)
      lock(conn, "pg_advisory_lock")
      task = Task.async(fn -> Brando.SoftDelete.Query.clean_up_soft_deletions() end)

      refute_receive {:mux, "DELETE", _path}, 300
      lock(conn, "pg_advisory_unlock")

      Task.await(task)
      assert_received {:mux, "DELETE", "/video/v1/assets/asset-1"}
    end
  end

  defp mux(timing) do
    put_test_env(Mux,
      access_token_id: "id",
      access_token_secret: "secret",
      delete_remote_on: timing,
      req_options: [plug: {Req.Test, Mux}]
    )
  end

  defp superuser(:legacy), do: Factory.insert(:random_user, role: :superuser)

  defp superuser(:groups) do
    put_test_env(:authorization_mode, :groups)
    superuser = Factory.insert(:random_user, role: :superuser)
    {:ok, _} = Migration.run()
    superuser
  end

  defp mux_uploaded(asset_id, opts \\ []) do
    meta = %{"provider" => "mux", "mux" => %{"asset_id" => asset_id, "playback_id" => "pb-#{asset_id}"}}

    Repo.insert!(%Video{
      type: :mux,
      title: "Asset #{asset_id}",
      status: :ready,
      meta: if(opts[:imported], do: Map.put(meta, "imported", true), else: meta)
    })
  end

  defp mux_asset(id) do
    %{
      "id" => id,
      "status" => "ready",
      "passthrough" => "Asset #{id}",
      "playback_ids" => [%{"id" => "pb-#{id}", "policy" => "public"}],
      "tracks" => []
    }
  end

  defp expire(video) do
    video |> Ecto.Changeset.change(deleted_at: DateTime.add(DateTime.utc_now(:second), -31, :day)) |> Repo.update!()
  end

  defp expire_deleted do
    Repo.update_all(from(v in Video, where: not is_nil(v.deleted_at)),
      set: [deleted_at: DateTime.add(DateTime.utc_now(:second), -31, :day)]
    )
  end

  # Restores `video` right after the purge's first read of the video table.
  defp restore_after_purge_reads(video) do
    handler = {__MODULE__, :restore, make_ref()}
    me = self()

    :telemetry.attach(
      handler,
      Repo.repo().config()[:telemetry_prefix] ++ [:query],
      fn _event, _measurements, metadata, _config ->
        if self() == me and metadata.source == "videos" and String.starts_with?(metadata.query, "SELECT") do
          :telemetry.detach(handler)
          video |> Ecto.Changeset.change(deleted_at: nil) |> Repo.update!()
        end
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
  end

  defp lock(conn, function) do
    Postgrex.query!(conn, "SELECT #{function}(hashtextextended($1, 0))", [lock_key()])
  end

  defp lock_key, do: "brando:provider_video:mux.asset_id:asset-1"

  defp assert_plays(video) do
    video = Repo.get!(Video, video.id)
    assert video.deleted_at == nil
    assert {:ok, "https://stream.mux.com/pb-asset-1.m3u8"} = Mux.get_playback_url(video)
  end
end

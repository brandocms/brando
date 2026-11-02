defmodule Brando.Videos.ProviderVideoRestoreTest do
  # A deleted provider video is not restored from the trash while a live
  # record of the same remote video is in its environment: that record was
  # added again from the provider's library meanwhile, and two live records
  # of one video break the provider webhooks, which expect one.
  use Brando.LiveCase, async: false

  import Brando.Test.Support, only: [put_test_env: 2]

  alias Brando.Authorization.Boundary
  alias Brando.Authorization.Groups
  alias Brando.Authorization.Migration
  alias Brando.Authorization.Scope
  alias Brando.Factory
  alias Brando.Repo
  alias Brando.Videos.ProviderHoldings
  alias Brando.Videos.Uploaders.Mux
  alias Brando.Videos.Video
  alias Phoenix.Socket.Broadcast

  setup do
    put_test_env(:tenancy_mode, :none)
    put_test_env(Mux, access_token_id: "id", access_token_secret: "secret", req_options: [plug: {Req.Test, Mux}])
    :ok
  end

  for authorization_mode <- [:legacy, :groups] do
    @authorization_mode authorization_mode

    test "a restore is refused while a live record plays the video, and allowed once it is gone, " <>
           "#{authorization_mode} authorization" do
      user = superuser(@authorization_mode)
      deleted = "asset-1" |> mux_video() |> soft_delete()
      live = mux_video("asset-1", imported: true, title: "Added again")

      assert {:error, {:recorded_here, %Video{id: live_id}}} = Boundary.restore(user, deleted)
      assert live_id == live.id
      assert Repo.get!(Video, deleted.id).deleted_at

      # A record of another video does not stand in the way.
      other = "asset-2" |> mux_video() |> soft_delete()
      assert {:ok, %Video{deleted_at: nil}} = Boundary.restore(user, other)

      soft_delete(live)
      assert {:ok, %Video{deleted_at: nil}} = Boundary.restore(user, deleted)
    end
  end

  for authorization_mode <- [:legacy, :groups] do
    @authorization_mode authorization_mode

    test "a record restored since it was read is returned as it is, #{authorization_mode} authorization" do
      user = superuser(@authorization_mode)
      live = "asset-1" |> mux_video() |> Ecto.Changeset.change(updated_at: ~N[2026-01-01 00:00:00]) |> Repo.update!()
      stale = %{live | deleted_at: DateTime.utc_now(:second)}

      assert {:ok, %Video{id: id, deleted_at: nil}} = Boundary.restore(user, stale)
      assert id == live.id
      assert Repo.get!(Video, live.id).updated_at == ~N[2026-01-01 00:00:00]
    end
  end

  # An imported record is purged without the video's lock. With groups
  # authorization, the change's check locks the row before the write, and
  # refuses one that is gone.
  test "a record purged between the restore's read and its write is not restored" do
    user = superuser(:legacy)
    deleted = "asset-1" |> mux_video(imported: true) |> soft_delete()
    purge_after_live_check(deleted)

    assert {:error, :not_found} = Boundary.restore(user, deleted)
    refute Repo.get(Video, deleted.id)
  end

  test "the trash says it could not restore a record purged since it was read", %{conn: conn, current_user: user} do
    deleted = "asset-1" |> mux_video() |> soft_delete()

    {:ok, view, _html} = live(conn, "/admin/assets/videos?status=deleted")
    Brando.endpoint().subscribe("user:#{user.id}")
    purge_after_read(view.pid, deleted)
    render_hook(view, "undelete_entry", %{"id" => to_string(deleted.id)})

    assert_receive %Broadcast{event: "toast", payload: %{payload: message}}, 2_000
    assert message =~ "Error undeleting"
    assert Process.alive?(view.pid)
  end

  describe "a restore while the video's lock is held" do
    setup do
      {:ok, conn} = Postgrex.start_link(Keyword.drop(Repo.repo().config(), [:pool, :ownership_pool, :pool_size, :name]))
      put_test_env(ProviderHoldings, lock_timeout: 300)
      {:ok, lock_conn: conn}
    end

    for authorization_mode <- [:legacy, :groups] do
      @authorization_mode authorization_mode

      # In groups mode the restore runs in a transaction, whose checkout
      # deadline is shorter than the lock's wait: the lock is waited for
      # before it opens.
      test "is refused as busy, the lock waited for outside a transaction, #{authorization_mode} authorization",
           %{lock_conn: conn} do
        user = superuser(@authorization_mode)
        deleted = "asset-1" |> mux_video() |> soft_delete()
        lock(conn, "pg_advisory_lock")
        report_lock_queries()

        assert {:error, :busy} = Boundary.restore(user, deleted)
        assert_received {:lock_query, false}
        refute_received {:lock_query, true}
        assert Repo.get!(Video, deleted.id).deleted_at

        lock(conn, "pg_advisory_unlock")
        assert {:ok, %Video{deleted_at: nil}} = Boundary.restore(user, deleted)
      end

      # The purge holds the lock while it deletes the row.
      test "a record purged while the restore waits for the lock is not restored, " <>
             "#{authorization_mode} authorization",
           %{lock_conn: conn} do
        user = superuser(@authorization_mode)
        deleted = "asset-1" |> mux_video() |> soft_delete()
        lock(conn, "pg_advisory_lock")
        purge_when_lock_busy(conn, deleted)

        assert {:error, :not_found} = Boundary.restore(user, deleted)
        refute Repo.get(Video, deleted.id)
      end
    end
  end

  test "the refusal names the live record to an editor who may read it" do
    user = superuser(:legacy)
    deleted = "asset-1" |> mux_video() |> soft_delete()
    mux_video("asset-1", imported: true, title: "Added again")

    assert {:error, {:recorded_here, live}} = Boundary.restore(user, deleted)
    assert Brando.Videos.restore_refused_message(live) =~ "Added again"
  end

  test "an editor who may not read the live record is refused all the same, without its title" do
    put_test_env(:authorization_mode, :groups)
    owner = Factory.insert(:random_user, role: :superuser)
    user = Factory.insert(:random_user, role: :user)
    {:ok, _} = Migration.run()

    deleted = "asset-1" |> mux_video() |> soft_delete()
    mux_video("asset-1", imported: true, title: "Added again")

    {:ok, group} =
      Groups.create(
        Scope.standalone(owner),
        %{name: "Restores videos"},
        ~w(brando.admin.access brando.videos.update brando.videos.restore)
      )

    {:ok, :ok} = Groups.add_member(Scope.standalone(owner), group.id, user.id)

    assert {:error, {:recorded_here, nil}} = Boundary.restore(user, deleted)
    assert Repo.get!(Video, deleted.id).deleted_at
  end

  test "the trash says why it refused, naming the live record", %{conn: conn, current_user: user} do
    deleted = "asset-1" |> mux_video() |> soft_delete()
    mux_video("asset-1", imported: true, title: "Added again")

    {:ok, view, _html} = live(conn, "/admin/assets/videos?status=deleted")
    Brando.endpoint().subscribe("user:#{user.id}")
    render_hook(view, "undelete_entry", %{"id" => to_string(deleted.id)})

    assert_receive %Broadcast{event: "toast", payload: %{payload: message}}, 2_000
    assert message =~ "Added again"
    assert Repo.get!(Video, deleted.id).deleted_at
  end

  # Sends whether each advisory lock query of this process ran in a
  # transaction.
  defp report_lock_queries do
    handler = {__MODULE__, :lock_queries, make_ref()}
    me = self()

    :telemetry.attach(
      handler,
      Repo.repo().config()[:telemetry_prefix] ++ [:query],
      fn _event, _measurements, metadata, _config ->
        if self() == me and metadata.query =~ "advisory",
          do: send(me, {:lock_query, Repo.repo().in_transaction?()})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
  end

  # The first time this process finds the video's lock taken, deletes
  # `video` and releases the lock that `conn` holds, as a purge would.
  defp purge_when_lock_busy(conn, video) do
    handler = {__MODULE__, :purge_when_lock_busy, make_ref()}
    me = self()

    :telemetry.attach(
      handler,
      Repo.repo().config()[:telemetry_prefix] ++ [:query],
      fn _event, _measurements, metadata, _config ->
        if self() == me and metadata.query =~ "pg_try_advisory" and match?({:ok, %{rows: [[false]]}}, metadata.result) do
          :telemetry.detach(handler)
          Repo.delete!(video)
          lock(conn, "pg_advisory_unlock")
        end
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
  end

  # Deletes `video` right after this process looks for a live record of the
  # same video, as a purge that takes no lock would.
  defp purge_after_live_check(video) do
    handler = {__MODULE__, :purge_after_live_check, make_ref()}
    me = self()

    :telemetry.attach(
      handler,
      Repo.repo().config()[:telemetry_prefix] ++ [:query],
      fn _event, _measurements, metadata, _config ->
        if self() == me and metadata.source == "videos" and metadata.query =~ "#>>" do
          :telemetry.detach(handler)
          Repo.delete!(video)
        end
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
  end

  # Deletes `video` right after `pid`'s next read of the video table, as a
  # purge between the trash's read and its restore would.
  defp purge_after_read(pid, video) do
    handler = {__MODULE__, :purge_after_read, make_ref()}

    :telemetry.attach(
      handler,
      Repo.repo().config()[:telemetry_prefix] ++ [:query],
      fn _event, _measurements, metadata, _config ->
        if self() == pid and metadata.source == "videos" and String.starts_with?(metadata.query, "SELECT") do
          :telemetry.detach(handler)
          Repo.delete!(video)
        end
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
  end

  defp lock(conn, function) do
    Postgrex.query!(conn, "SELECT #{function}(hashtextextended($1, 0))", ["brando:provider_video:mux.asset_id:asset-1"])
  end

  defp superuser(:legacy), do: Factory.insert(:random_user, role: :superuser)

  defp superuser(:groups) do
    put_test_env(:authorization_mode, :groups)
    superuser = Factory.insert(:random_user, role: :superuser)
    {:ok, _} = Migration.run()
    superuser
  end

  defp mux_video(asset_id, opts \\ []) do
    meta = %{"provider" => "mux", "mux" => %{"asset_id" => asset_id, "playback_id" => "pb-#{asset_id}"}}

    Repo.insert!(%Video{
      type: :mux,
      title: opts[:title] || "Asset #{asset_id}",
      status: :ready,
      meta: if(opts[:imported], do: Map.put(meta, "imported", true), else: meta)
    })
  end

  defp soft_delete(video), do: video |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second)) |> Repo.update!()
end

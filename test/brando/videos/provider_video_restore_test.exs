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

defmodule BrandoAdmin.VideoListFetchDetailsTest do
  # Synchronous: Bunny's configuration is the application's, read by every test
  use Brando.LiveCase, async: false

  import Ecto.Query, only: [where: 2]

  alias Brando.Factory
  alias Brando.Videos.Uploaders.Bunny

  setup do
    put_test_env(Bunny, api_key: "key", library_id: "133", req_options: [plug: {Req.Test, Bunny}])
    :ok
  end

  defp bunny_video(guid) do
    Factory.insert(:video,
      type: :bunny,
      status: :ready,
      title: "Bunny #{guid}",
      meta: %{
        "bunny" => %{
          "video_guid" => guid,
          "available_resolutions" => "360p",
          "has_mp4_fallback" => true,
          "thumbnail_url" => "thumbnail.jpg"
        }
      }
    )
  end

  defp select(view, ids) do
    [cid] = view |> render() |> Floki.parse_document!() |> Floki.attribute(".selection-clear", "phx-target")

    for id <- ids do
      view
      |> with_target("[data-phx-component='#{cid}']")
      |> render_click("select_row", %{"id" => to_string(id), "shiftKey" => "true"})
    end
  end

  # A ready Bunny video lacks nothing, so the header's button leaves it out;
  # the selection's Fetch details looks it up all the same, and picks up a
  # thumbnail set in Bunny since.
  test "Fetch details looks up the selected videos, a ready Bunny video too, and skips the rest", %{conn: conn} do
    video = bunny_video("renamed")
    upload = Factory.insert(:video, type: :upload, title: "Uploaded")
    refute video.id in Brando.Videos.list_video_ids_missing_metadata()

    Req.Test.stub(Bunny, fn conn ->
      Req.Test.json(conn, %{
        "guid" => "renamed",
        "availableResolutions" => "360p",
        "hasMP4Fallback" => true,
        "thumbnailFileName" => "thumbnail_2bbb8a75.jpg"
      })
    end)

    {:ok, view, _html} = live(conn, "/admin/assets/videos")
    select(view, [video.id, upload.id])

    view |> element("button[phx-click='fetch_selected_metadata']") |> render_click()

    # Oban runs inline in tests
    assert Brando.Repo.reload!(video).meta["bunny"]["thumbnail_url"] == "thumbnail_2bbb8a75.jpg"
    assert Brando.Repo.reload!(upload).updated_at == upload.updated_at

    # The upload is left out, rather than counted as a failed lookup
    BrandoAdmin.Work.Registry.sync()

    assert %BrandoAdmin.Work{status: :finished, total: 1} =
             :sys.get_state(view.pid).socket.assigns.work["video-metadata-selected"]
  end

  test "Fetch details with nothing it can look up queues nothing", %{conn: conn} do
    upload = Factory.insert(:video, type: :upload, title: "Uploaded")

    Oban.Testing.with_testing_mode(:manual, fn ->
      {:ok, view, _html} = live(conn, "/admin/assets/videos")
      render_click(view, "fetch_selected_metadata", %{"ids" => Jason.encode!([upload.id])})

      assert Brando.Repo.all(where(Oban.Job, worker: "Brando.Worker.VideoMetadata")) == []
      BrandoAdmin.Work.Registry.sync()
      refute BrandoAdmin.Work.get(:sys.get_state(view.pid).socket.assigns.current_user, "video-metadata-selected")
    end)
  end

  test "Fetch details is refused to a legacy user demoted since the list opened" do
    editor = Factory.insert(:random_user, role: :editor, config: %Brando.Users.UserConfig{})
    video = bunny_video("refused")
    conn = log_in_user(Phoenix.ConnTest.build_conn(), editor)
    Req.Test.stub(Bunny, fn _conn -> flunk("Bunny was asked") end)

    Oban.Testing.with_testing_mode(:manual, fn ->
      {:ok, view, _html} = live(conn, "/admin/assets/videos")
      Brando.Repo.update_all(Ecto.Query.from(u in Brando.Users.User, where: u.id == ^editor.id), set: [role: :user])

      # The view ends, for the client to rejoin at the stored role
      Process.flag(:trap_exit, true)
      catch_exit(render_click(view, "fetch_selected_metadata", %{"ids" => Jason.encode!([video.id])}))
      assert Brando.Repo.all(where(Oban.Job, worker: "Brando.Worker.VideoMetadata")) == []
    end)
  end
end

defmodule BrandoAdmin.VideoListLiveTest do
  use Brando.LiveCase

  alias Brando.Factory
  alias Brando.Videos

  test "a video is renamed in place, played in a dialog, and shows where it is used", %{conn: conn} do
    video = Factory.insert(:video, title: nil)

    {:ok, view, html} = live(conn, "/admin/assets/videos")
    assert html =~ "Not in use"

    view
    |> form("#list-row-#{video.id} .library-video-rename", %{"video_id" => video.id, "title" => "Example Hotel"})
    |> render_submit()

    assert {:ok, %{title: "Example Hotel"}} = Videos.get_video(%{matches: %{id: video.id}})

    view |> element("#list-row-#{video.id} .library-video-play") |> render_click()
    assert has_element?(view, "#video-player-modal iframe[src*='youtube.com/embed/#{video.remote_id}']")

    render_click(view, "close_video", %{})
    refute has_element?(view, "#video-player-modal")
  end

  # A Bunny or Mux video has no thumbnail image of its own until one is
  # fetched; the row shows its provider's frame meanwhile, as the picker does.
  test "a provider video without a thumbnail image shows its provider's frame", %{conn: conn} do
    video = Factory.insert(:video, type: :mux, remote_id: "m1", meta: %{"mux" => %{"playback_id" => "pb-1"}})
    stream = Factory.insert(:video, type: :external_file, source_url: "https://vz-abc.b-cdn.net/0f1e2d3c/playlist.m3u8")

    {:ok, view, _html} = live(conn, "/admin/assets/videos")

    assert has_element?(
             view,
             ~s(#list-row-#{video.id} .library-video-play img[src="https://image.mux.com/pb-1/thumbnail.jpg"])
           )

    assert has_element?(
             view,
             ~s(#list-row-#{stream.id} .library-video-play img[src="https://vz-abc.b-cdn.net/0f1e2d3c/thumbnail.jpg"])
           )
  end

  # Every video missing a thumbnail or title gets a lookup, one insert each:
  # the list queues one job that does that, and shows the lookups as one
  # piece of work beside the button.
  test "fetching missing details queues one job for the lookups", %{conn: conn} do
    video = Factory.insert(:video, title: nil)
    Req.Test.stub(Brando.Videos.Metadata, &Plug.Conn.send_resp(&1, 404, ""))

    test = self()
    handler = "video-metadata-insert-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:oban, :engine, :insert_job, :start],
      fn _event, _measurements, %{changeset: changeset}, _config ->
        send(test, {:queued, Ecto.Changeset.get_field(changeset, :worker), Ecto.Changeset.get_field(changeset, :args)})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    {:ok, view, _html} = live(conn, "/admin/assets/videos")
    view |> element("button[phx-click='fetch_metadata']") |> render_click()

    # Oban runs inline in tests: the sweep, then the lookup it queued.
    assert_received {:queued, "Brando.Worker.VideoMetadataSweep", _args}
    assert_received {:queued, "Brando.Worker.VideoMetadata", %{"video_id" => video_id}}
    assert video_id == video.id

    # The source answered 404: the lookup gave up, and the video still misses its details
    BrandoAdmin.Work.Registry.sync()

    assert has_element?(
             view,
             ~s(.work-status[data-work-id="video-metadata"][data-status="failed"]),
             "Some videos could not be looked up"
           )

    assert has_element?(view, "button[phx-click='fetch_metadata']:not([disabled])")
  end

  test "fetching details shows the lookups running, and their result when they are in", %{conn: conn} do
    Factory.insert(:video, title: nil)
    {:ok, view, _html} = live(conn, "/admin/assets/videos")
    user = :sys.get_state(view.pid).socket.assigns.current_user

    # As the sweep reports, before its lookups end
    BrandoAdmin.Work.start(user, "video-metadata", "Looking up 2 videos", total: 2, done: "Thumbnails and titles fetched")
    BrandoAdmin.Work.advance(user, "video-metadata")
    BrandoAdmin.Work.Registry.sync()

    assert has_element?(view, "button[phx-click='fetch_metadata'][disabled][aria-busy]", "Fetching thumbnails and titles")
    assert has_element?(view, ~s(.work-status[data-status="running"] .work-count), "1 / 2")

    BrandoAdmin.Work.advance(user, "video-metadata")
    BrandoAdmin.Work.Registry.sync()

    assert has_element?(view, ~s(.work-status[data-status="finished"]), "Thumbnails and titles fetched")
    refute has_element?(view, "button[phx-click='fetch_metadata'][disabled]")

    # A reload while it ran shows it running
    BrandoAdmin.Work.start(user, "video-metadata", "Looking up 1 video", total: 1)
    BrandoAdmin.Work.Registry.sync()
    {:ok, view, _html} = live(conn, "/admin/assets/videos")
    assert has_element?(view, "button[phx-click='fetch_metadata'][aria-busy]")
    BrandoAdmin.Work.finish(user, "video-metadata")
  end

  test "the Not in use filter lists unused videos, and switching it off drops it", %{conn: conn} do
    unused = Factory.insert(:video, title: "Loose end")

    {:ok, view, _html} = live(conn, "/admin/assets/videos")

    view |> element(".boolean-filter input") |> render_click()
    assert_patch(view) =~ "filter%3Aunused=true"
    assert has_element?(view, "#list-row-#{unused.id}")
    assert has_element?(view, ".active-filters .filter", "Not in use")

    view |> element(".boolean-filter input") |> render_click()
    refute assert_patch(view) =~ "unused"
    refute has_element?(view, ".active-filters")
  end
end

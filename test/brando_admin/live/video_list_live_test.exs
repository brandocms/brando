defmodule BrandoAdmin.VideoListLiveTest do
  use Brando.LiveCase

  alias Brando.Factory
  alias Brando.Videos

  test "a video is renamed in place, played in a dialog, and shows where it is used", %{conn: conn} do
    video = Factory.insert(:video, title: nil)

    {:ok, view, html} = live(conn, "/admin/assets/videos")
    assert html =~ "Not in use"

    view
    |> form("#list-row-#{video.id} .library-video-rename", %{"video_id" => video.id, "title" => "Sommerro"})
    |> render_submit()

    assert {:ok, %{title: "Sommerro"}} = Videos.get_video(%{matches: %{id: video.id}})

    view |> element("#list-row-#{video.id} .library-video-play") |> render_click()
    assert has_element?(view, "#video-player-modal iframe[src*='youtube.com/embed/#{video.remote_id}']")

    render_click(view, "close_video", %{})
    refute has_element?(view, "#video-player-modal")
  end

  # Every video missing a thumbnail or title is queued, one insert each:
  # with thousands, the list would hang for as long as that took.
  test "fetching missing details queues the lookups away from the list", %{conn: conn} do
    video = Factory.insert(:video, title: nil)
    Req.Test.stub(Brando.Videos.Metadata, &Plug.Conn.send_resp(&1, 404, ""))

    test = self()
    handler = "video-metadata-insert-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:oban, :engine, :insert_job, :start],
      fn _event, _measurements, %{changeset: changeset}, _config ->
        if Ecto.Changeset.get_field(changeset, :worker) == "Brando.Worker.VideoMetadata",
          do: send(test, {:queued_by, self(), Ecto.Changeset.get_field(changeset, :args)["video_id"]})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    {:ok, view, _html} = live(conn, "/admin/assets/videos")
    view |> element("button[phx-click='fetch_metadata']") |> render_click()
    render_async(view)

    assert_received {:queued_by, pid, video_id}
    assert video_id == video.id
    refute pid == view.pid
    refute has_element?(view, "button[phx-click='fetch_metadata']")
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

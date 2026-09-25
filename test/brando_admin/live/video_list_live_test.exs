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
end

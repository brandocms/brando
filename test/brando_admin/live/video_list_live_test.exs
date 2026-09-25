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

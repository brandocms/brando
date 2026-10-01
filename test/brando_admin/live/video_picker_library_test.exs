defmodule BrandoAdmin.VideoPickerLibraryTest do
  @moduledoc """
  "Add from <provider>" in the video picker: browse the provider's own library
  and add one of its videos, mounted in a real entry form.
  """
  use Brando.LiveCase

  alias Brando.Videos.Uploaders.Vimeo

  setup %{current_user: user} do
    put_test_env(Vimeo, access_token: "vimeo-token", req_options: [plug: {Req.Test, Vimeo}])
    Req.Test.set_req_test_to_shared()
    on_exit(fn -> Req.Test.set_req_test_to_private() end)

    Req.Test.stub(Vimeo, fn
      %{request_path: "/me/videos"} = conn ->
        videos =
          case conn.query_params["query"] do
            "harbour" -> [vimeo_video("11", "Harbour at dawn", "available")]
            _ -> [vimeo_video("11", "Harbour at dawn", "available"), vimeo_video("12", "Rough cut", "transcoding")]
          end

        Req.Test.json(conn, %{"paging" => %{"next" => nil}, "data" => videos})

      %{request_path: "/videos/11"} = conn ->
        Req.Test.json(conn, vimeo_video("11", "Harbour at dawn", "available"))
    end)

    {:ok, page: Factory.insert(:page, creator: user)}
  end

  test "lists the provider library and adds a video to Brando's", %{conn: conn, page: page} do
    {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")

    view |> element("#video-picker button", "Add from Vimeo") |> render_click()
    html = render_async(view)

    assert html =~ "Vimeo library"
    assert html =~ "Harbour at dawn"
    assert html =~ "0:30 · 1280 × 720 · 2026-09-01"
    # Still transcoding: shown, but nothing to add yet.
    assert view |> element(~s([data-remote-id="12"])) |> render() =~ "Processing"
    refute has_element?(view, ~s([data-remote-id="12"] button))

    view |> element(~s([data-remote-id="11"] button), "Add") |> render_click()

    video = Brando.Videos.get_video_by_meta("vimeo.video_id", "11")
    assert %{type: :vimeo_account, status: :ready, meta: %{"imported" => true}} = video
    assert view |> element(~s([data-remote-id="11"])) |> render() =~ "In library"

    # Adding it again selects the same record.
    view |> element(~s([data-remote-id="11"] button), "Select") |> render_click()
    assert Brando.Repo.aggregate(Brando.Videos.Video, :count) == 1
  end

  test "searches the library", %{conn: conn, page: page} do
    {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")

    view |> element("#video-picker button", "Add from Vimeo") |> render_click()
    render_async(view)

    view |> form("#video-picker .video-picker-library-search", %{query: "harbour"}) |> render_submit()
    html = render_async(view)

    assert html =~ "Harbour at dawn"
    refute html =~ "Rough cut"
  end

  test "is not offered without provider credentials", %{conn: conn, page: page} do
    put_test_env(Vimeo, [])

    {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")

    refute has_element?(view, "#video-picker button", "Add from Vimeo")
  end

  defp vimeo_video(id, name, status) do
    %{
      "uri" => "/videos/#{id}",
      "name" => name,
      "link" => "https://vimeo.com/#{id}",
      "status" => status,
      "transcode" => %{"status" => if(status == "available", do: "complete", else: "in_progress")},
      "width" => 1280,
      "height" => 720,
      "duration" => 30,
      "created_time" => "2026-09-01T10:00:00+00:00",
      "files" => [%{"quality" => "hls", "link" => "https://player.vimeo.com/external/#{id}.m3u8?s=x"}]
    }
  end
end

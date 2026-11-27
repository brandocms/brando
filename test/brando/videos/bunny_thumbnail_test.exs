defmodule Brando.Videos.BunnyThumbnailTest do
  # The CDN hostname is application configuration, read by every test
  use ExUnit.Case, async: false

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias Brando.Videos.Helpers
  alias Brando.Videos.Uploaders.Bunny
  alias Brando.Videos.Video

  setup do
    previous = Application.get_env(:brando, Bunny)
    Application.put_env(:brando, Bunny, cdn_hostname: "vz-test.b-cdn.net")

    on_exit(fn ->
      if previous,
        do: Application.put_env(:brando, Bunny, previous),
        else: Application.delete_env(:brando, Bunny)
    end)
  end

  defp video(bunny_meta) do
    %Video{
      type: :bunny,
      status: :ready,
      aspect_ratio: "16/9",
      meta: %{"bunny" => Map.put(bunny_meta, "video_guid", "guid-1")}
    }
  end

  defp poster(video) do
    assigns = %{video: video}

    html =
      rendered_to_string(~H"""
      <Brando.HTML.Video.video video={@video} opts={[]} />
      """)

    [_, poster] = Regex.run(~r/poster="([^"]+)"/, html)
    poster
  end

  test "the site poster and the admin thumbnail use the stored thumbnail name" do
    video = video(%{"thumbnail_url" => "thumbnail_2bbb8a75.jpg"})

    assert poster(video) == "https://vz-test.b-cdn.net/guid-1/thumbnail_2bbb8a75.jpg"
    assert Helpers.thumbnail_url(video) == "https://vz-test.b-cdn.net/guid-1/thumbnail_2bbb8a75.jpg"
  end

  test "without a stored name, both fall back to thumbnail.jpg" do
    for bunny_meta <- [%{}, %{"thumbnail_url" => nil}, %{"thumbnail_url" => ""}] do
      video = video(bunny_meta)

      assert poster(video) == "https://vz-test.b-cdn.net/guid-1/thumbnail.jpg"
      assert Helpers.thumbnail_url(video) == "https://vz-test.b-cdn.net/guid-1/thumbnail.jpg"
    end
  end

  test "a name that is not a plain file name falls back to thumbnail.jpg" do
    for name <- [
          "../other-guid/thumbnail.jpg",
          "nested/thumbnail.jpg",
          "back\\slash.jpg",
          "..",
          "https://evil.example/x.jpg",
          "javascript:alert(1)",
          "thumbnail.jpg?x=1",
          "thumbnail.jpg#x",
          "thumb nail.jpg",
          ~s(thumb"nail.jpg)
        ] do
      video = video(%{"thumbnail_url" => name})

      assert poster(video) == "https://vz-test.b-cdn.net/guid-1/thumbnail.jpg", name
      assert Helpers.thumbnail_url(video) == "https://vz-test.b-cdn.net/guid-1/thumbnail.jpg", name
    end
  end

  test "the admin thumbnail is still nil before the video is ready and without a CDN hostname" do
    video = video(%{"thumbnail_url" => "thumbnail_2bbb8a75.jpg"})

    assert Helpers.thumbnail_url(%{video | status: :processing}) == nil

    Application.put_env(:brando, Bunny, [])
    assert Helpers.thumbnail_url(video) == nil
  end
end

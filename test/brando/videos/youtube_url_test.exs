defmodule Brando.Videos.YouTubeURLTest do
  use ExUnit.Case, async: true

  alias Brando.Videos.YouTubeURL

  describe "parse/1" do
    for url <- [
          "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
          "http://www.youtube.com/watch?v=dQw4w9WgXcQ",
          "HTTPS://WWW.YOUTUBE.COM/watch?v=dQw4w9WgXcQ",
          "https://youtube.com/watch?list=PL1&v=dQw4w9WgXcQ&t=10",
          "https://m.youtube.com/watch?v=dQw4w9WgXcQ",
          "https://music.youtube.com/watch?v=dQw4w9WgXcQ",
          "https://youtu.be/dQw4w9WgXcQ",
          "https://youtu.be/dQw4w9WgXcQ?si=abc",
          "https://www.youtube.com/embed/dQw4w9WgXcQ",
          "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?rel=0",
          "https://www.youtube.com/shorts/dQw4w9WgXcQ",
          "https://www.youtube.com/live/dQw4w9WgXcQ?feature=share",
          "https://www.youtube.com/v/dQw4w9WgXcQ",
          "www.youtube.com/watch?v=dQw4w9WgXcQ",
          "youtu.be/dQw4w9WgXcQ",
          "//www.youtube.com/watch?v=dQw4w9WgXcQ",
          "  https://youtu.be/dQw4w9WgXcQ\n"
        ] do
      test "reads the id from #{inspect(url)}" do
        assert YouTubeURL.parse(unquote(url)) == {:ok, "dQw4w9WgXcQ"}
      end
    end

    for url <- [
          "javascript:document.title='f05'",
          "javascript:document.title='f05'//watch?v=dQw4w9WgXcQ",
          "javascript://www.youtube.com/watch?v=dQw4w9WgXcQ",
          "data:text/html,youtube.com/watch?v=dQw4w9WgXcQ",
          "ftp://www.youtube.com/watch?v=dQw4w9WgXcQ",
          "https://example.com/watch?v=dQw4w9WgXcQ",
          "https://www.youtube.com.example.com/watch?v=dQw4w9WgXcQ",
          "https://notyoutube.com/watch?v=dQw4w9WgXcQ",
          "https://www.youtube.com@example.com/watch?v=dQw4w9WgXcQ",
          "https://www.youtube.com/watch",
          "https://www.youtube.com/watch?v=",
          "https://www.youtube.com/watch?v=a%22b",
          "https://www.youtube.com/watch?v=../../x",
          "https://www.youtube.com/channel/dQw4w9WgXcQ",
          "https://youtu.be/",
          "https://youtu.be/a/b",
          ""
        ] do
      test "refuses #{inspect(url)}" do
        assert YouTubeURL.parse(unquote(url)) == :error
      end
    end

    test "refuses what is not a string" do
      assert YouTubeURL.parse(nil) == :error
    end
  end

  describe "embed_url/2" do
    @embed "https://www.youtube.com/embed/dQw4w9WgXcQ"

    test "uses the row's id" do
      assert YouTubeURL.embed_url(%{remote_id: "dQw4w9WgXcQ", source_url: nil}) == @embed
      assert YouTubeURL.embed_url(%{remote_id: "dQw4w9WgXcQ", source_url: "javascript:x"}) == @embed
    end

    test "reads a row with only an address" do
      assert YouTubeURL.embed_url(%{remote_id: nil, source_url: "https://youtu.be/dQw4w9WgXcQ"}) == @embed
    end

    test "appends params" do
      assert YouTubeURL.embed_url(%{remote_id: "dQw4w9WgXcQ"}, autoplay: 1) == @embed <> "?autoplay=1"
    end

    # The older parser kept what followed the id
    test "falls back to the address when the stored id is not an id" do
      video = %{remote_id: "dQw4w9WgXcQ?t=5", source_url: "https://youtu.be/dQw4w9WgXcQ?t=5"}

      assert YouTubeURL.embed_url(video) == @embed
    end

    test "is nil for an id that is not one and an address that is not YouTube's" do
      assert YouTubeURL.embed_url(%{remote_id: ~s(x"/onload="y), source_url: "javascript:x"}) == nil
      assert YouTubeURL.embed_url(%{remote_id: "../../evil", source_url: nil}) == nil
      assert YouTubeURL.embed_url(%{}) == nil
    end
  end
end

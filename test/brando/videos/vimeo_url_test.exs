defmodule Brando.Videos.VimeoURLTest do
  use ExUnit.Case, async: true

  alias Brando.Videos.Video
  alias Brando.Videos.VimeoURL

  describe "parse/1" do
    test "reads the id and the unlisted hash from every link shape Vimeo hands out" do
      for {url, expected} <- [
            {"https://vimeo.com/123456789", %{id: "123456789", hash: nil}},
            {"https://vimeo.com/123456789/abcdef1234", %{id: "123456789", hash: "abcdef1234"}},
            {"https://vimeo.com/123456789/abcdef1234?share=copy", %{id: "123456789", hash: "abcdef1234"}},
            {"https://vimeo.com/123456789?share=copy", %{id: "123456789", hash: nil}},
            {"vimeo.com/123456789", %{id: "123456789", hash: nil}},
            {"https://www.vimeo.com/channels/staffpicks/123456789", %{id: "123456789", hash: nil}},
            {"https://vimeo.com/showcase/111/video/123456789", %{id: "123456789", hash: nil}},
            {"https://vimeo.com/manage/videos/123456789/abcdef1234", %{id: "123456789", hash: "abcdef1234"}},
            {"https://player.vimeo.com/video/123456789?h=abcdef1234&badge=0", %{id: "123456789", hash: "abcdef1234"}},
            {"//player.vimeo.com/video/123456789", %{id: "123456789", hash: nil}}
          ] do
        assert VimeoURL.parse(url) == {:ok, expected}, url
      end
    end

    test "leaves file links and other hosts alone" do
      assert VimeoURL.parse("https://player.vimeo.com/external/123456789.hd.mp4?s=x") == :error
      assert VimeoURL.parse("https://player.vimeo.com/progressive_redirect/playback/1/rendition/720p/file.mp4") == :error
      assert VimeoURL.parse("https://notvimeo.com/123456789") == :error
      assert VimeoURL.parse("https://youtube.com/watch?v=123") == :error
      assert VimeoURL.parse(nil) == :error
    end
  end

  describe "embed_url/2" do
    test "carries an unlisted video's hash into the player URL" do
      video = %Video{type: :vimeo, remote_id: "123456789", source_url: "https://vimeo.com/123456789/abcdef1234"}

      assert VimeoURL.embed_url(video, dnt: 1) == "https://player.vimeo.com/video/123456789?h=abcdef1234&dnt=1"
    end

    test "repairs rows saved with the hash folded into remote_id" do
      video = %Video{type: :vimeo, remote_id: "123456789/abcdef1234", source_url: nil}

      assert VimeoURL.embed_url(video) == "https://player.vimeo.com/video/123456789?h=abcdef1234"
    end

    test "reads a block's url key" do
      block = %{type: :vimeo, remote_id: "123456789/abcdef1234", url: "https://vimeo.com/123456789/abcdef1234"}

      assert VimeoURL.embed_url(block, autoplay: 1) ==
               "https://player.vimeo.com/video/123456789?h=abcdef1234&autoplay=1"
    end

    test "a public video has no h parameter" do
      assert VimeoURL.embed_url(%{remote_id: "42"}) == "https://player.vimeo.com/video/42"
      assert VimeoURL.embed_url(%{remote_id: nil}) == nil
    end
  end

  test "page_url/1 is what oEmbed needs to see an unlisted video" do
    assert VimeoURL.page_url(%{id: "1", hash: nil}) == "https://vimeo.com/1"
    assert VimeoURL.page_url(%{id: "1", hash: "abcdef1234"}) == "https://vimeo.com/1/abcdef1234"
  end
end

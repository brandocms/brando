defmodule BrandoAdmin.Components.VideoPlayerTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Brando.Videos.Video
  alias BrandoAdmin.Components.Form.VideoDrawer
  alias BrandoAdmin.Components.VideoPlayer

  @embed "https://www.youtube.com/embed/dQw4w9WgXcQ?autoplay=1"
  @script_scheme "javascript:document.title='f05'"

  defp player(attrs), do: render_component(&VideoPlayer.player/1, video: struct(Video, attrs))

  describe "player/1, a YouTube video" do
    test "embeds its id" do
      assert player(type: :youtube, remote_id: "dQw4w9WgXcQ") =~ ~s(src="#{@embed}")
    end

    test "embeds the id in an address when the row has only that" do
      assert player(type: :youtube, source_url: "https://youtu.be/dQw4w9WgXcQ") =~ ~s(src="#{@embed}")
    end

    test "never embeds an address, nor an id that is not one" do
      for attrs <- [[source_url: @script_scheme], [remote_id: ~s(../../x"/onload="y)]] do
        html = player([type: :youtube] ++ attrs)

        refute html =~ "<iframe"
        assert html =~ "video-player-unavailable"
      end
    end
  end

  describe "player/1, a Vimeo account video without a file link" do
    test "embeds the id and hash in its meta" do
      meta = %{"vimeo" => %{"video_id" => "76979871", "hash" => "abcdef1234"}}

      assert player(type: :vimeo_account, meta: meta) =~
               ~s(src="https://player.vimeo.com/video/76979871?h=abcdef1234&amp;autoplay=1")
    end

    test "reads its address when it has no Vimeo meta" do
      assert player(type: :vimeo_account, source_url: "https://vimeo.com/76979871", meta: %{}) =~
               ~s(src="https://player.vimeo.com/video/76979871?autoplay=1")
    end
  end

  describe "the video drawer's source link" do
    test "links a stored address" do
      video = %{type: :external_file, source_url: "https://example.com/clip.mp4"}
      assert VideoDrawer.source_link(video) == video.source_url

      video = %{type: :vimeo, source_url: "vimeo.com/76979871"}
      assert VideoDrawer.source_link(video) == video.source_url
    end

    test "leaves out a stored address with another scheme" do
      for type <- [:external_file, :vimeo, :youtube] do
        assert VideoDrawer.source_link(%{type: type, source_url: @script_scheme}) == nil
        assert VideoDrawer.source_link(%{type: type, source_url: "\tjava\nscript:x"}) == nil
      end
    end
  end
end

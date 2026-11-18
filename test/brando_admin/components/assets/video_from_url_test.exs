defmodule BrandoAdmin.Components.Assets.VideoFromURLTest do
  # "Add from URL", shared by the video picker and the Videos library: what
  # the URL hook's event becomes, and what the lookup finds. The oEmbed
  # endpoint is stubbed.
  use Brando.ConnCase

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias BrandoAdmin.Components.Assets.VideoFromURL

  describe "video_params/1" do
    test "a YouTube address" do
      assert VideoFromURL.video_params(%{
               "width" => 1280,
               "height" => 720,
               "source" => "youtube",
               "remoteId" => "dQw4w9WgXcQ",
               "url" => "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
             }) ==
               {:ok,
                %{
                  type: :youtube,
                  source_url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
                  remote_id: "dQw4w9WgXcQ",
                  width: 1280,
                  height: 720,
                  aspect_ratio: "16:9"
                }}
    end

    test "an address the hook could not read gives no video" do
      # `new URL()` throws without a scheme; the hook then sends no provider or id
      assert VideoFromURL.video_params(%{"width" => 0, "height" => 0, "url" => "www.youtube.com/watch?v=x"}) == :error
      assert VideoFromURL.video_params(%{}) == :error
    end

    test "a Vimeo address takes its id from the URL, not the parser's rest of the path" do
      params = %{
        "width" => 640,
        "height" => 480,
        "source" => "vimeo",
        "remoteId" => "76979871/abcdef1234",
        "url" => "https://vimeo.com/76979871/abcdef1234"
      }

      assert {:ok, %{type: :vimeo, remote_id: "76979871", aspect_ratio: "4:3"}} = VideoFromURL.video_params(params)
    end

    test "anything else is an external file" do
      params = %{"width" => 0, "height" => 0, "source" => "file", "remoteId" => "x", "url" => "https://a.test/x.m3u8"}
      assert {:ok, %{type: :external_file, aspect_ratio: "16:9"}} = VideoFromURL.video_params(params)
    end
  end

  test "aspect_ratio/2 names the common ratios and spells out the rest" do
    assert VideoFromURL.aspect_ratio(1920, 1080) == "16:9"
    assert VideoFromURL.aspect_ratio(1080, 1920) == "9:16"
    assert VideoFromURL.aspect_ratio(1000, 1000) == "1:1"
    assert VideoFromURL.aspect_ratio(1000, 300) == "1000:300"
    assert VideoFromURL.aspect_ratio(0, 0) == "16:9"
    assert VideoFromURL.aspect_ratio(nil, nil) == "16:9"
  end

  test "title_from_url/1 reads the file name" do
    assert VideoFromURL.title_from_url("https://cdn.test/media/launch_reel-01.mp4?x=1") == "launch reel 01"
    assert VideoFromURL.title_from_url("https://cdn.test/") == "Video"
  end

  describe "metadata/2" do
    setup do
      put_test_env(Brando.OEmbed, req_options: [plug: {Req.Test, Brando.OEmbed}])
      :ok
    end

    test "asks the provider's oEmbed endpoint" do
      Req.Test.stub(Brando.OEmbed, fn conn ->
        assert conn.host == "www.youtube.com"

        Req.Test.json(conn, %{
          "title" => "Never gonna",
          "description" => "A classic",
          "thumbnail_url" => "https://i.test/t.jpg"
        })
      end)

      assert VideoFromURL.metadata(:youtube, "https://www.youtube.com/watch?v=dQw4w9WgXcQ") ==
               {"Never gonna", "A classic", "https://i.test/t.jpg"}
    end

    test "a provider that doesn't answer gives a placeholder title" do
      Req.Test.stub(Brando.OEmbed, &Plug.Conn.send_resp(&1, 500, ""))
      assert VideoFromURL.metadata(:vimeo, "https://vimeo.com/1") == {"Vimeo Video", nil, nil}
    end

    test "a file is not looked up" do
      Req.Test.stub(Brando.OEmbed, fn _conn -> flunk("asked the provider") end)
      assert VideoFromURL.metadata(:external_file, "https://cdn.test/clip.mp4") == {"clip", nil, nil}
    end
  end

  describe "input/1" do
    test "pushes to the component given, else to its own element" do
      assert render_component(&VideoFromURL.input/1, id: "p", target: "#host", creating: false) =~
               ~s(data-target="#host")

      html = render_component(&VideoFromURL.input/1, id: "lib", creating: false)
      assert html =~ ~s(id="video-url-parser-lib")
      assert html =~ ~s(data-target="#video-url-parser-lib")
      assert html =~ ~s(<div class="video-picker-analyzing hidden">)
    end

    test "keeps the spinner up while the provider is asked" do
      html = render_component(&VideoFromURL.input/1, id: "lib", creating: true)
      assert html =~ "Creating..."
      refute html =~ "video-picker-analyzing hidden"
    end
  end
end

defmodule Brando.Villain.ParserTest do
  use ExUnit.Case
  use BrandoIntegration.TestCase
  use Brando.ConnCase

  import __MODULE__.Parser

  test "header/2" do
    assert IO.iodata_to_binary(header(%{text: "Header"}, [])) == ~s(<h1>Header</h1>)
    assert IO.iodata_to_binary(header(%{text: "Header", level: "5"}, [])) == ~s(<h5>Header</h5>)

    assert header(%{text: "Header", level: "5", anchor: "test"}, []) ==
             ~s(<a name="test"></a><h5>Header</h5>)
  end

  test "text/2" do
    assert text(%{text: "**Some** text here.", type: "paragraph"}, []) ==
             ~s(**Some** text here.)

    assert text(%{text: "**Some** text here.", type: "lead"}, []) ==
             ~s(<div class=\"lead\">**Some** text here.</div>)

    assert text(%{text: "<h3>A header here</h3><p>Followed by some text</p>"}, []) ==
             "<h3>A header here</h3><p>Followed by some text</p>"

    assert text(%{text: ~s(<p class="lede">A styled paragraph</p>), type: "paragraph"}, []) ==
             ~s(<p class="lede">A styled paragraph</p>)
  end

  test "map/2" do
    assert map(%{embed_url: "https://nrk.no", source: :gmaps}, []) ==
             "<div class=\"map-wrapper\">\n         <iframe width=\"420\"\n                 height=\"315\"\n                 src=\"https://nrk.no\"\n                 frameborder=\"0\"\n                 allowfullscreen>\n         </iframe>\n       </div>"
  end

  test "html/2" do
    assert html(%{text: "<h1>test</h1>"}, []) == "<h1>test</h1>"
  end

  test "video/2 youtube" do
    assert video(%{remote_id: "asdf1234", type: :youtube, autoplay: false}, []) ==
             "<div class=\"video-wrapper video-embed\" data-orientation=\"landscape\" style=\"--aspect-ratio: 0.75\">\n         <iframe width=\"420\"\n                 height=\"315\"\n                 src=\"//www.youtube.com/embed/asdf1234?autoplay=0&controls=0&showinfo=0&rel=0\"\n                 frameborder=\"0\"\n                 allowfullscreen>\n         </iframe>\n       </div>"
  end

  test "video/2 vimeo" do
    assert video(%{remote_id: "asdf1234", type: :vimeo}, []) ==
             "<div class=\"video-wrapper video-embed\" data-orientation=\"landscape\" style=\"--aspect-ratio: 0.562\">\n         <iframe src=\"//player.vimeo.com/video/asdf1234?dnt=1\"\n                 width=\"500\"\n                 height=\"281\"\n                 frameborder=\"0\"\n                 webkitallowfullscreen\n                 mozallowfullscreen\n                 allowfullscreen>\n         </iframe>\n       </div>"
  end

  test "video/2 youtube keeps start time from url" do
    html =
      video(
        %{
          remote_id: "asdf1234",
          type: :youtube,
          autoplay: false,
          url: "https://www.youtube.com/watch?v=asdf1234&t=2m45s"
        },
        []
      )

    assert html =~ "&start=165"
  end

  test "video/2 youtube omits start when url has no t param" do
    html =
      video(
        %{remote_id: "asdf1234", type: :youtube, autoplay: false, url: "https://youtu.be/asdf1234"},
        []
      )

    refute html =~ "&start="
  end

  test "video/2 vimeo falls back on nil dimensions without crashing" do
    html = video(%{remote_id: "asdf1234", type: :vimeo, width: nil, height: nil}, [])

    assert html =~ ~s(width="500")
    assert html =~ ~s(height="281")
  end

  test "video/2 vimeo parses string dimensions to integers" do
    html = video(%{remote_id: "asdf1234", type: :vimeo, width: "640", height: "360"}, [])

    assert html =~ ~s(width="640")
    assert html =~ ~s(height="360")
  end

  test "video/2 file" do
    assert video(
             %{
               play_button: false,
               source_url: "my_video.mp4",
               type: :external_file,
               width: 300,
               height: 300,
               autoplay: true,
               poster: false,
               preload: nil,
               opacity: 0
             },
             []
           ) ==
             "<div class=\"video-wrapper video-file\" data-smart-video data-orientation=\"portrait\" data-preload=\"my_video.mp4\" data-src=\"my_video.mp4\" data-autoplay style=\"--aspect-ratio: 1.0; --aspect-ratio-division: 300/300;\">\n  <video width=\"300\" height=\"300\" alt=\"\" tabindex=\"0\" preload=\"auto\" autoplay muted loop playsinline data-video style=\"--aspect-ratio: 1.0; --aspect-ratio-division: 300/300;\" data-src=\"my_video.mp4\">\n  </video>\n\n  <noscript>\n    <video width=\"300\" height=\"300\" alt=\"\" tabindex=\"0\" preload=\"metadata\" muted loop playsinline src=\"my_video.mp4\">\n    </video>\n  </noscript>\n\n  \n\n  \n    \n      \n         <div data-cover>\n           <img\n             width=\"300\"\n             height=\"300\"\n             alt=\"Video cover image\"\n             src=\"data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%27300%27%20height%3D%27300%27%20style%3D%27background%3Argba%280%2C0%2C0%2C0%29%27%2F%3E\" />\n         </div>\n       \n    \n  \n  \n</div>"
  end

  test "video/2 file with caption" do
    assert video(
             %{
               play_button: false,
               source_url: "my_video.mp4",
               type: :external_file,
               width: 300,
               height: 300,
               autoplay: true,
               poster: false,
               preload: nil,
               opacity: 0,
               title: "<p>This is a caption</p>"
             },
             []
           ) ==
             "<div class=\"video-wrapper video-file\" data-smart-video data-orientation=\"portrait\" data-preload=\"my_video.mp4\" data-src=\"my_video.mp4\" data-autoplay style=\"--aspect-ratio: 1.0; --aspect-ratio-division: 300/300;\">\n  <video width=\"300\" height=\"300\" alt=\"\" tabindex=\"0\" preload=\"auto\" autoplay muted loop playsinline data-video style=\"--aspect-ratio: 1.0; --aspect-ratio-division: 300/300;\" data-src=\"my_video.mp4\">\n  </video>\n\n  <noscript>\n    <video width=\"300\" height=\"300\" alt=\"\" tabindex=\"0\" preload=\"metadata\" muted loop playsinline src=\"my_video.mp4\">\n    </video>\n  </noscript>\n\n  \n\n  \n    \n      \n         <div data-cover>\n           <img\n             width=\"300\"\n             height=\"300\"\n             alt=\"Video cover image\"\n             src=\"data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%27300%27%20height%3D%27300%27%20style%3D%27background%3Argba%280%2C0%2C0%2C0%29%27%2F%3E\" />\n         </div>\n       \n    \n  \n  <figcaption><p>This is a caption</p></figcaption>\n</div>"
  end

  test "video/2 upload" do
    result =
      video(
        %{
          play_button: false,
          remote_id: "videos/default/my_video.mp4",
          type: :upload,
          width: 300,
          height: 300,
          autoplay: true,
          poster: false,
          preload: nil,
          opacity: 0
        },
        []
      )

    assert result =~ "video-wrapper"
    assert result =~ "videos/default/my_video.mp4"
    refute result =~ "TODO"
  end

  test "divider/2" do
    assert divider("whatever", []) == ~s(<hr>)
  end

  test "list/2" do
    assert list(
             %{
               id: "ul_id",
               class: "ul_class",
               rows: [
                 %{class: "test", value: "val here!"},
                 %{value: "val 2 here!"}
               ]
             },
             []
           ) ==
             "<ul id=\"ul_id\" class=\"ul_class\">\n  <li class=\"test\">\n  val here!\n</li>\n\n<li>\n  val 2 here!\n</li>\n\n</ul>\n"
  end

  test "blockquote/2" do
    assert blockquote(%{text: "Some text", cite: "J. Williamson"}, []) ==
             "<blockquote>\n  <p>\nSome text</p>\n\n  <p class=\"cite\">\n    — <cite>J. Williamson</cite>\n  </p>\n</blockquote>\n"

    assert blockquote(%{text: "Some text", cite: ""}, []) ==
             "<blockquote>\n  <p>\nSome text</p>\n\n</blockquote>\n"
  end
end

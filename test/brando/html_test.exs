defmodule Brando.HTMLTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase
  use RouterHelper
  import Brando.HTML
  import Brando.Utils, only: [media_url: 0]
  import Phoenix.LiveViewTest
  import Phoenix.Component
  alias Brando.Factory

  doctest Brando.HTML

  test "first_name/1" do
    assert first_name("John Josephs") == "John"
    assert first_name("John-Christian Josephs") == "John-Christian"
  end

  test "zero_pad/1" do
    assert zero_pad(1) == "001"
    assert zero_pad(10) == "010"
    assert zero_pad(100) == "100"
    assert zero_pad(1000) == "1000"
    assert zero_pad("1") == "001"
    assert zero_pad("1", 10) == "0000000001"
  end

  test "body_tag" do
    assigns = %{}

    comp = ~H"""
    <.body_tag conn={%{private: %{brando_css_classes: "one two three"}}} id="top">
      hello!
    </.body_tag>
    """

    assert rendered_to_string(comp) =~
             ~s(<body id="top" class="one two three unloaded" data-vsn=\"#{Brando.version()}\">)

    comp = ~H"""
    <.body_tag conn={%{private: %{brando_css_classes: "one two three", brando_section_name: "some-section"}}} id="top">
      hello!
    </.body_tag>
    """

    assert rendered_to_string(comp) =~
             "<body id=\"top\" class=\"one two three unloaded\" data-script=\"some-section\" data-vsn=\"#{Brando.version()}\">"
  end

  test "cookie_law" do
    assigns = %{}

    comp = ~H"""
    <.cookie_law>
      Inside text
    </.cookie_law>
    """

    assert rendered_to_string(comp) ==
             "<div class=\"container cookie-container\">\n  <div class=\"cookie-container-inner\">\n    <div class=\"cookie-law\">\n      <div class=\"cookie-law-text\">\n        <p>\n  Inside text\n</p>\n      </div>\n      <div class=\"cookie-law-buttons\">\n        <button class=\"dismiss-cookielaw\">\n          OK\n        </button>\n        \n          <a href=\"/cookies\" class=\"info-cookielaw\">\n            More info\n          </a>\n        \n      </div>\n    </div>\n  </div>\n</div>"
  end

  test "google_analytics" do
    assigns = %{}

    comp = ~H"""
    <.google_analytics code="asdf123" />
    """

    assert rendered_to_string(comp) =~ "ga('create','asdf123','auto')"
  end

  test "truncate" do
    assert truncate("hello", 7) == "hello"
    assert truncate("hello", 2) == "hel..."
    assert truncate(5, 5) == 5
  end

  test "render_meta" do
    mock_conn = %Plug.Conn{assigns: %{language: "en"}, private: %{plug_session: %{}}}

    assigns = %{mock_conn: mock_conn}

    comp = ~H"""
    <.render_meta conn={@mock_conn} />
    """

    html = rendered_to_string(comp)

    assert html =~ ~s(<meta property="og:site_name" content="MyApp">)
    assert html =~ ~s(<meta property="og:title" content="Fallback meta title">)
    assert html =~ ~s(<meta property="og:url" content="http://localhost">)
    assert html =~ ~s(<meta name="title" content="Fallback meta title">)
  end

  test "active/2" do
    conn = build_conn(:get, "/some/link")
    assert active(conn, "/some/link") == "active"
    assert active(conn, "/some/other/link") == ""
  end

  test "video_tag with invalid poster" do
    opts = [
      width: 400,
      height: 300,
      opacity: 0.5,
      preload: true,
      cover: :svg,
      poster: "my_poster.jpg",
      autoplay: true
    ]

    assigns = %{opts: opts}

    comp = ~H"""
    <.video video="https://src.vid" opts={@opts} />
    """

    assert rendered_to_string(comp) ==
             "<div class=\"video-wrapper video-file\" data-smart-video data-orientation=\"landscape\" data-preload=\"https://src.vid\" data-src=\"https://src.vid\" data-autoplay style=\"--aspect-ratio: 0.75; --aspect-ratio-division: 400/300;\">\n  <video width=\"400\" height=\"300\" alt=\"\" tabindex=\"0\" preload=\"auto\" autoplay muted loop playsinline data-video style=\"--aspect-ratio: 0.75; --aspect-ratio-division: 400/300;\" data-src=\"https://src.vid\">\n  </video>\n\n  <noscript>\n    <video width=\"400\" height=\"300\" alt=\"\" tabindex=\"0\" preload=\"metadata\" muted loop playsinline src=\"https://src.vid\">\n    </video>\n  </noscript>\n\n  \n\n  \n    \n      \n         <div data-cover>\n           <img\n             width=\"400\"\n             height=\"300\"\n             alt=\"Video cover image\"\n             src=\"data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%27400%27%20height%3D%27300%27%20style%3D%27background%3Argba%280%2C0%2C0%2C0.5%29%27%2F%3E\" />\n         </div>\n       \n    \n  \n  \n</div>"
  end

  test "video_tag with valid poster" do
    opts = [
      width: 400,
      height: 300,
      opacity: 0.5,
      preload: true,
      cover: :svg,
      poster: "/images/my_poster.jpg",
      autoplay: true
    ]

    assigns = %{opts: opts}

    comp = ~H"""
    <.video video="https://src.vid" opts={@opts} />
    """

    assert rendered_to_string(comp) ==
             "<div class=\"video-wrapper video-file\" data-smart-video data-orientation=\"landscape\" data-preload=\"https://src.vid\" data-src=\"https://src.vid\" data-autoplay style=\"--aspect-ratio: 0.75; --aspect-ratio-division: 400/300;\">\n  <video width=\"400\" height=\"300\" alt=\"\" tabindex=\"0\" preload=\"auto\" autoplay muted loop playsinline data-video poster=\"/images/my_poster.jpg\" style=\"--aspect-ratio: 0.75; --aspect-ratio-division: 400/300;\" data-src=\"https://src.vid\">\n  </video>\n\n  <noscript>\n    <video width=\"400\" height=\"300\" alt=\"\" tabindex=\"0\" preload=\"metadata\" muted loop playsinline src=\"https://src.vid\">\n    </video>\n  </noscript>\n\n  \n\n  \n    \n      \n         <div data-cover>\n           <img\n             width=\"400\"\n             height=\"300\"\n             alt=\"Video cover image\"\n             src=\"data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%27400%27%20height%3D%27300%27%20style%3D%27background%3Argba%280%2C0%2C0%2C0.5%29%27%2F%3E\" />\n         </div>\n       \n    \n  \n  \n</div>"
  end

  test "video component with %Video{type: :upload}" do
    video_struct = %Brando.Videos.Video{
      type: :upload,
      remote_id: "videos/default/test.mp4",
      width: 1920,
      height: 1080,
      aspect_ratio: "1920/1080",
      autoplay: false,
      controls: true,
      loop: false,
      status: :ready
    }

    assigns = %{video_struct: video_struct, opts: []}

    comp = ~H"""
    <.video video={@video_struct} opts={@opts} />
    """

    result = rendered_to_string(comp)
    assert result =~ "video-wrapper video-file"
    assert result =~ "videos/default/test.mp4"
    assert result =~ "controls"
  end

  test "video component with %Video{type: :external_file}" do
    video_struct = %Brando.Videos.Video{
      type: :external_file,
      source_url: "https://example.com/video.mp4",
      width: 1280,
      height: 720,
      aspect_ratio: "1280/720",
      autoplay: true,
      controls: false,
      status: :ready
    }

    assigns = %{video_struct: video_struct, opts: []}

    comp = ~H"""
    <.video video={@video_struct} opts={@opts} />
    """

    result = rendered_to_string(comp)
    assert result =~ "video-wrapper video-file"
    assert result =~ "https://example.com/video.mp4"
    assert result =~ "data-autoplay"
  end

  test "video component with %Video{type: :external_file} and nil source_url" do
    video_struct = %Brando.Videos.Video{
      type: :external_file,
      source_url: nil,
      status: :ready
    }

    assigns = %{video_struct: video_struct, opts: []}

    comp = ~H"""
    <.video video={@video_struct} opts={@opts} />
    """

    result = rendered_to_string(comp)
    assert result =~ "video-wrapper"
  end

  test "video component with a ready Cloudflare Stream video" do
    hls_url = "https://customer.example.com/video-id/manifest/video.m3u8"
    thumbnail_url = "https://customer.example.com/video-id/thumbnails/thumbnail.jpg"

    video_struct = %Brando.Videos.Video{
      type: :cloudflare,
      status: :ready,
      width: 1920,
      height: 1080,
      aspect_ratio: "1920/1080",
      controls: true,
      meta: %{
        "cloudflare" => %{
          "uid" => "video-id",
          "playback_hls" => hls_url,
          "thumbnail_url" => thumbnail_url
        }
      }
    }

    assigns = %{video_struct: video_struct, opts: []}

    result =
      rendered_to_string(~H"""
      <.video video={@video_struct} opts={@opts} />
      """)

    assert result =~ hls_url
    assert result =~ thumbnail_url
    assert result =~ "video-wrapper video-cloudflare"
    assert result =~ ~s(controls)
  end

  describe "video playback settings" do
    defp mux_video(fields) do
      struct!(
        %Brando.Videos.Video{
          type: :mux,
          status: :ready,
          width: 1920,
          height: 1080,
          aspect_ratio: "1920/1080",
          meta: %{"mux" => %{"playback_id" => "pb123"}}
        },
        fields
      )
    end

    defp render_video(video, opts) do
      assigns = %{video_struct: video, opts: opts}

      rendered_to_string(~H"""
      <.video video={@video_struct} opts={@opts} />
      """)
    end

    # The `:vimeo` and `:youtube` clauses destructured `%{assigns: %{video: …}}`
    # while every other clause takes the assigns directly. A function component
    # is never handed a wrapper, so neither could match and both raised
    # FunctionClauseError — reachable from `{% video entry.video %}` and from a
    # gallery holding an embed.
    test "an embed record renders through the component instead of raising" do
      youtube = %Brando.Videos.Video{
        type: :youtube,
        remote_id: "abc123",
        width: 1920,
        height: 1080
      }

      vimeo = %Brando.Videos.Video{type: :vimeo, remote_id: "987654", width: 640, height: 360}

      youtube_html = render_video(youtube, [])
      assert youtube_html =~ "youtube.com/embed/abc123"
      assert youtube_html =~ ~s(width="1920")

      vimeo_html = render_video(vimeo, [])
      assert vimeo_html =~ "player.vimeo.com/video/987654"
      assert vimeo_html =~ ~s(width="640")
    end

    test "a youtube embed reads autoplay and controls from opts" do
      video = %Brando.Videos.Video{type: :youtube, remote_id: "abc123", width: 100, height: 100}

      # `&` is escaped in the attribute
      assert render_video(video, autoplay: true, controls: true) =~ "autoplay=1&amp;controls=1"
      assert render_video(video, []) =~ "autoplay=0&amp;controls=0"
    end

    test "a provider video with no opts uses the record's settings" do
      result = render_video(mux_video(autoplay: true, controls: true), [])

      assert result =~ "video-wrapper video-mux"
      assert result =~ "https://stream.mux.com/pb123.m3u8"
      assert result =~ "data-autoplay"
      assert result =~ "controls"
    end

    test "an opt overrides the record, including when the opt is false" do
      video = mux_video(autoplay: true, controls: true)

      refute render_video(video, autoplay: false) =~ "data-autoplay"
      refute render_video(video, controls: false) =~ "controls"
    end

    test "a record that turns a setting off beats the built-in default" do
      # `loop` defaults to true, so the `||` chain this replaced could never
      # see an editor's "off".
      refute render_video(mux_video(loop: false), []) =~ "loop"
      assert render_video(mux_video(loop: nil), []) =~ "loop"
    end

    test "muted is honoured on its own, not only as a side effect of autoplay" do
      assert render_video(mux_video(muted: true), []) =~ "muted"
      assert render_video(mux_video(muted: nil), muted: true) =~ "muted"
      refute render_video(mux_video(muted: nil), []) =~ "muted"
    end

    test "the record's dimensions win over the ones implied by the aspect ratio" do
      result = render_video(mux_video(width: 1920, height: 1080), [])

      assert result =~ ~s(width="1920")
      assert result =~ ~s(height="1080")
      assert result =~ "landscape"
    end

    test "an unparseable aspect ratio does not raise" do
      result = render_video(mux_video(width: nil, height: nil, aspect_ratio: "1.77:1"), [])

      assert result =~ "video-wrapper video-mux"
      refute result =~ ~s(width=")
    end

    test "a Bunny video is record-aware too" do
      video = %Brando.Videos.Video{
        type: :bunny,
        status: :ready,
        width: 1280,
        height: 720,
        aspect_ratio: "1280/720",
        controls: true,
        meta: %{"bunny" => %{"video_guid" => "guid-1", "library_id" => 42}}
      }

      result = render_video(video, [])

      assert result =~ "video-wrapper video-bunny"
      assert result =~ "guid-1/playlist.m3u8"
      assert result =~ "controls"
    end

    test "captions stay opt-in but can now resolve to the record" do
      video = mux_video(caption: "From the editor", title: "The title")

      refute render_video(video, []) =~ "figcaption"
      assert render_video(video, caption: true) =~ "<figcaption>From the editor</figcaption>"
      assert render_video(video, caption: true, title: "From the tag") =~ "From the tag"
      assert render_video(mux_video(caption: nil, title: "The title"), caption: true) =~ "The title"
    end
  end

  test "picture_tag" do
    user = Factory.build(:user)
    srcset = {Brando.Users.User, :avatar}

    opts = [
      srcset: srcset,
      prefix: media_url(),
      key: :small,
      picture_class: "avatar",
      img_class: "img-fluid"
    ]

    assigns = %{user: user, opts: opts}

    comp = ~H"""
    <.picture src={@user.avatar} opts={@opts} />
    """

    doc =
      comp
      |> rendered_to_string()
      |> Floki.parse_document!()

    assert doc
           |> Floki.find("figure")
           |> assert_attr("data-orientation", ["landscape"])

    assert doc
           |> Floki.find("picture")
           |> assert_attr("data-orientation", ["landscape"])
           |> assert_attr("class", ["avatar"])

    assert doc
           |> Floki.find("source")
           |> assert_attr("srcset", [
             "/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w"
           ])
           |> assert_attr("type", ["image/jpeg"])

    assert doc
           |> Floki.find("picture > img")
           |> assert_attr("class", ["img-fluid"])
           |> assert_attr("src", ["/media/images/avatars/small/27i97a.jpeg"])
           |> assert_attr("srcset", [
             "/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w"
           ])
           |> assert_attr("alt", [""])

    assert doc
           |> Floki.find("noscript > img")
           |> assert_attr("src", ["/media/images/avatars/small/27i97a.jpeg"])

    # ---
    opts = [
      srcset: srcset,
      prefix: media_url(),
      key: :small,
      picture_class: "avatar",
      img_class: "img-fluid"
    ]

    assigns = %{avatar: Map.put(user.avatar, :formats, [:jpg, :webp]), opts: opts}

    comp = ~H"""
    <.picture src={@avatar} opts={@opts} />
    """

    doc =
      comp
      |> rendered_to_string()
      |> Floki.parse_document!()

    [source_webp, source_jpeg] = Floki.find(doc, "source")

    assert source_webp
           |> assert_attr("type", ["image/webp"])
           |> assert_attr("srcset", [
             "/media/images/avatars/small/27i97a.webp 300w, /media/images/avatars/medium/27i97a.webp 500w, /media/images/avatars/large/27i97a.webp 700w"
           ])

    assert source_jpeg
           |> assert_attr("type", ["image/jpeg"])
           |> assert_attr("srcset", [
             "/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w"
           ])

    assert doc
           |> Floki.find("picture > img")
           |> assert_attr("src", ["/media/images/avatars/small/27i97a.jpeg"])

    # ---
    opts = [
      srcset: srcset,
      prefix: media_url(),
      key: :small,
      picture_class: "avatar",
      img_class: "img-fluid"
    ]

    assigns = %{avatar: Map.put(user.avatar, :formats, [:jpg, :webp, :avif]), opts: opts}

    comp = ~H"""
    <.picture src={@avatar} opts={@opts} />
    """

    doc =
      comp
      |> rendered_to_string()
      |> Floki.parse_document!()

    [source_avif, source_webp, source_jpeg] = Floki.find(doc, "source")

    assert source_avif
           |> assert_attr("type", ["image/avif"])
           |> assert_attr("srcset", [
             "/media/images/avatars/small/27i97a.avif 300w, /media/images/avatars/medium/27i97a.avif 500w, /media/images/avatars/large/27i97a.avif 700w"
           ])

    assert source_webp
           |> assert_attr("type", ["image/webp"])
           |> assert_attr("srcset", [
             "/media/images/avatars/small/27i97a.webp 300w, /media/images/avatars/medium/27i97a.webp 500w, /media/images/avatars/large/27i97a.webp 700w"
           ])

    assert source_jpeg
           |> assert_attr("type", ["image/jpeg"])
           |> assert_attr("srcset", [
             "/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w"
           ])

    assert doc
           |> Floki.find("picture > img")
           |> assert_attr("src", ["/media/images/avatars/small/27i97a.jpeg"])

    # ---
    opts = [
      srcset: srcset,
      prefix: media_url(),
      key: :small,
      caption: true,
      picture_class: "avatar",
      img_class: "img-fluid"
    ]

    assigns = %{user: user, opts: opts}

    comp = ~H"""
    <.picture src={@user.avatar} opts={@opts} />
    """

    doc =
      comp
      |> rendered_to_string()
      |> Floki.parse_document!()

    assert Floki.find(doc, "figcaption") == [{"figcaption", [], ["Title!"]}]
    # ---
    opts = [
      srcset: srcset,
      prefix: media_url(),
      key: :small,
      caption: "A custom caption",
      picture_class: "avatar",
      img_class: "img-fluid"
    ]

    assigns = %{user: user, opts: opts}

    comp = ~H"""
    <.picture src={@user.avatar} opts={@opts} />
    """

    doc =
      comp
      |> rendered_to_string()
      |> Floki.parse_document!()

    assert Floki.find(doc, "figcaption") == [{"figcaption", [], ["A custom caption"]}]

    # ---
    opts = [
      srcset: srcset,
      prefix: media_url(),
      key: :small,
      height: true,
      width: true,
      picture_class: "avatar",
      img_class: "img-fluid"
    ]

    assigns = %{user: user, opts: opts}

    comp = ~H"""
    <.picture src={@user.avatar} opts={@opts} />
    """

    doc =
      comp
      |> rendered_to_string()
      |> Floki.parse_document!()

    assert doc
           |> Floki.find("picture > img")
           |> assert_attr("height", ["200"])
           |> assert_attr("width", ["300"])
           |> assert_attr("alt", [""])

    assert doc
           |> Floki.find("figure")
           |> assert_attr("data-orientation", ["landscape"])

    # ---
    opts = [
      srcset: srcset,
      prefix: media_url(),
      key: :small,
      height: 200,
      width: 200,
      picture_class: "avatar",
      img_class: "img-fluid"
    ]

    assigns = %{user: user, opts: opts}

    comp = ~H"""
    <.picture src={@user.avatar} opts={@opts} />
    """

    doc =
      comp
      |> rendered_to_string()
      |> Floki.parse_document!()

    assert doc
           |> Floki.find("picture > img")
           |> assert_attr("height", ["200"])
           |> assert_attr("width", ["200"])
           |> assert_attr("alt", [""])

    assert doc
           |> Floki.find("figure")
           |> assert_attr("data-orientation", ["landscape"])

    # ---
    opts = [
      lightbox: true,
      srcset: srcset,
      prefix: media_url(),
      key: :small,
      height: 200,
      width: 200,
      picture_class: "avatar",
      img_class: "img-fluid"
    ]

    assigns = %{user: user, opts: opts}

    comp = ~H"""
    <.picture src={@user.avatar} opts={@opts} />
    """

    doc =
      comp
      |> rendered_to_string()
      |> Floki.parse_document!()

    assert doc
           |> Floki.find("a")
           |> assert_attr("href", ["/media/images/avatars/small/27i97a.jpeg"])
           |> assert_attr("data-lightbox", ["/media/images/avatars/small/27i97a.jpeg"])

    # ---
    opts = [
      lightbox: true,
      srcset: srcset,
      prefix: media_url(),
      key: :small,
      placeholder: :svg,
      lazyload: true,
      height: 200,
      width: 200,
      picture_class: "avatar",
      img_class: "img-fluid"
    ]

    assigns = %{user: user, opts: opts}

    comp = ~H"""
    <.picture src={@user.avatar} opts={@opts} />
    """

    doc =
      comp
      |> rendered_to_string()
      |> Floki.parse_document!()

    assert doc
           |> Floki.find("a")
           |> assert_attr("href", ["/media/images/avatars/small/27i97a.jpeg"])
           |> assert_attr("data-lightbox", ["/media/images/avatars/small/27i97a.jpeg"])

    assert doc
           |> Floki.find("picture")
           |> assert_attr("data-ll-srcset", ["data-ll-srcset"])

    assert doc
           |> Floki.find("picture > img")
           |> assert_attr("data-ll-placeholder", ["data-ll-placeholder"])
           |> assert_attr("data-ll-srcset-image", ["data-ll-srcset-image"])
           |> assert_attr("data-src", [
             "data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%27300%27%20height%3D%27200%27%20style%3D%27background%3Argba%280%2C0%2C0%2C0.05%29%27%2F%3E"
           ])
           |> assert_attr("src", [
             "data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%27300%27%20height%3D%27200%27%20style%3D%27background%3Argba%280%2C0%2C0%2C0.05%29%27%2F%3E"
           ])

    # ---
    opts = [
      lightbox: true,
      srcset: srcset,
      prefix: media_url(),
      key: :small,
      placeholder: :svg,
      lazyload: true,
      height: 200,
      width: 200,
      picture_class: "avatar",
      img_class: "img-fluid"
    ]

    assigns = %{avatar: Map.put(user.avatar, :formats, [:jpg, :webp]), opts: opts}

    comp = ~H"""
    <.picture src={@avatar} opts={@opts} />
    """

    doc =
      comp
      |> rendered_to_string()
      |> Floki.parse_document!()

    assert doc
           |> Floki.find("a")
           |> assert_attr("href", ["/media/images/avatars/small/27i97a.jpeg"])
           |> assert_attr("data-lightbox", ["/media/images/avatars/small/27i97a.jpeg"])

    assert doc
           |> Floki.find("picture")
           |> assert_attr("data-ll-srcset", ["data-ll-srcset"])

    assert doc
           |> Floki.find("picture > img")
           |> assert_attr("data-ll-placeholder", ["data-ll-placeholder"])
           |> assert_attr("data-ll-srcset-image", ["data-ll-srcset-image"])
           |> assert_attr("data-src", [
             "data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%27300%27%20height%3D%27200%27%20style%3D%27background%3Argba%280%2C0%2C0%2C0.05%29%27%2F%3E"
           ])
           |> assert_attr("src", [
             "data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%27300%27%20height%3D%27200%27%20style%3D%27background%3Argba%280%2C0%2C0%2C0.05%29%27%2F%3E"
           ])

    [source_webp, source_jpeg] = Floki.find(doc, "source")

    assert source_webp
           |> assert_attr("type", ["image/webp"])
           |> assert_attr("data-srcset", [
             "/media/images/avatars/small/27i97a.webp 300w, /media/images/avatars/medium/27i97a.webp 500w, /media/images/avatars/large/27i97a.webp 700w"
           ])

    assert source_jpeg
           |> assert_attr("type", ["image/jpeg"])
           |> assert_attr("data-srcset", [
             "/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w"
           ])

    # ---
    opts = [
      srcset: srcset,
      prefix: media_url(),
      key: :small,
      picture_class: "avatar",
      img_class: "img-fluid",
      lazyload: true,
      placeholder: :micro
    ]

    assigns = %{user: user, opts: opts}

    comp = ~H"""
    <.picture src={@user.avatar} opts={@opts} />
    """

    doc =
      comp
      |> rendered_to_string()
      |> Floki.parse_document!()

    assert doc
           |> Floki.find("picture")
           |> assert_attr("data-ll-srcset", ["data-ll-srcset"])

    assert doc
           |> Floki.find("picture > img")
           |> assert_attr("data-ll-placeholder", ["data-ll-placeholder"])
           |> assert_attr("data-ll-srcset-image", ["data-ll-srcset-image"])
           |> assert_attr("data-src", ["/media/images/avatars/small/27i97a.jpeg"])
           |> assert_attr("src", ["/media/images/avatars/micro/27i97a.jpeg"])

    # ---
    opts = [
      srcset: srcset,
      prefix: media_url(),
      key: :small,
      picture_class: "avatar",
      img_class: "img-fluid",
      placeholder: :svg,
      lazyload: true
    ]

    assigns = %{user: user, opts: opts}

    comp = ~H"""
    <.picture src={@user.avatar} opts={@opts} />
    """

    doc =
      comp
      |> rendered_to_string()
      |> Floki.parse_document!()

    assert doc
           |> Floki.find("picture")
           |> assert_attr("data-ll-srcset", ["data-ll-srcset"])

    assert doc
           |> Floki.find("picture > img")
           |> assert_attr("data-ll-placeholder", ["data-ll-placeholder"])
           |> assert_attr("data-ll-srcset-image", ["data-ll-srcset-image"])
           |> assert_attr("data-src", [
             "data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%27300%27%20height%3D%27200%27%20style%3D%27background%3Argba%280%2C0%2C0%2C0.05%29%27%2F%3E"
           ])
           |> assert_attr("src", [
             "data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%27300%27%20height%3D%27200%27%20style%3D%27background%3Argba%280%2C0%2C0%2C0.05%29%27%2F%3E"
           ])

    # ---

    project_cover = %Brando.Images.Image{
      alt: nil,
      cdn: false,
      config_target: "image:Brando.BlueprintTest.Project:cover",
      credits: nil,
      deleted_at: nil,
      dominant_color: "#080808",
      focal: %Brando.Images.Focal{x: 50, y: 50},
      formats: [:jpg],
      height: 2000,
      id: 30,
      inserted_at: ~N[2022-02-28 16:41:22],
      path: "projects/covers/1qn45539cgnh.png",
      sizes: %{
        "large" => "projects/covers/large/1qn45539cgnh.jpg",
        "medium" => "projects/covers/medium/1qn45539cgnh.jpg",
        "micro" => "projects/covers/micro/1qn45539cgnh.jpg",
        "small" => "projects/covers/small/1qn45539cgnh.jpg",
        "thumb" => "projects/covers/thumb/1qn45539cgnh.jpg",
        "xlarge" => "projects/covers/xlarge/1qn45539cgnh.jpg",
        "crop_small" => "projects/covers/crop_small/1qn45539cgnh.jpg",
        "crop_medium" => "projects/covers/crop_medium/1qn45539cgnh.jpg"
      },
      status: :processed,
      title: nil,
      updated_at: ~N[2022-02-28 16:41:24],
      width: 1000
    }

    opts = [
      srcset: {Brando.BlueprintTest.Project, :cover, :cropped},
      prefix: media_url(),
      key: :small,
      picture_class: "avatar",
      img_class: "img-fluid",
      placeholder: :dominant_color,
      lazyload: true
    ]

    assigns = %{project_cover: project_cover, opts: opts}

    comp = ~H"""
    <.picture src={@project_cover} opts={@opts} />
    """

    doc =
      comp
      |> rendered_to_string()
      |> Floki.parse_document!()

    assert doc
           |> Floki.find("figure")
           |> assert_attr("data-placeholder", ["dominant_color"])

    assert doc
           |> Floki.find("picture")
           |> assert_attr("class", ["avatar"])
           |> assert_attr("style", ["background-color: #080808"])
           |> assert_attr("data-ll-srcset", ["data-ll-srcset"])

    assert doc
           |> Floki.find("picture > img")
           |> assert_attr("data-ll-placeholder", ["data-ll-placeholder"])
           |> assert_attr("data-ll-srcset-image", ["data-ll-srcset-image"])
           |> assert_attr("width", ["1000"])
           |> assert_attr("height", ["1000"])
           |> assert_attr("data-src", [
             "data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%271000%27%20height%3D%271000%27%20style%3D%27background%3Argba%280%2C0%2C0%2C0%29%27%2F%3E"
           ])
           |> assert_attr("src", [
             "data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%271000%27%20height%3D%271000%27%20style%3D%27background%3Argba%280%2C0%2C0%2C0%29%27%2F%3E"
           ])

    # default cropped srcset
    opts = [
      srcset: {Brando.BlueprintTest.Project, :cover, :default},
      prefix: media_url(),
      key: :small,
      picture_class: "avatar",
      img_class: "img-fluid",
      placeholder: :dominant_color,
      lazyload: true
    ]

    assigns = %{project_cover: project_cover, opts: opts}

    comp = ~H"""
    <.picture src={@project_cover} opts={@opts} />
    """

    doc =
      comp
      |> rendered_to_string()
      |> Floki.parse_document!()

    assert doc
           |> Floki.find("picture > img")
           |> assert_attr("width", ["1000"])
           |> assert_attr("height", ["1000"])
           |> assert_attr("data-src", [
             "data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%271000%27%20height%3D%271000%27%20style%3D%27background%3Argba%280%2C0%2C0%2C0%29%27%2F%3E"
           ])
           |> assert_attr("src", [
             "data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%271000%27%20height%3D%271000%27%20style%3D%27background%3Argba%280%2C0%2C0%2C0%29%27%2F%3E"
           ])

    # ---
    media_queries = [
      {"(min-width: 0px) and (max-width: 760px)", [{"mobile", "700w"}]}
    ]

    opts = [
      srcset: srcset,
      media_queries: media_queries,
      prefix: media_url(),
      key: :small,
      picture_class: "avatar",
      img_class: "img-fluid"
    ]

    assigns = %{user: user, opts: opts}

    comp = ~H"""
    <.picture src={@user.avatar} opts={@opts} />
    """

    doc =
      comp
      |> rendered_to_string()
      |> Floki.parse_document!()

    [source_mq, source_jpeg] = Floki.find(doc, "source")

    assert source_mq
           |> assert_attr("media", ["(min-width: 0px) and (max-width: 760px)"])
           |> assert_attr("srcset", ["/media/images/avatars/mobile/27i97a.jpeg 700w"])

    assert source_jpeg
           |> assert_attr("type", ["image/jpeg"])
           |> assert_attr("srcset", [
             "/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w"
           ])

    # ---
    opts = [
      alt: "hepp!",
      srcset: srcset,
      media_queries: media_queries,
      prefix: media_url(),
      key: :small,
      picture_attrs: [data_test: true, data_test_params: "hepp"],
      img_attrs: [data_test2: true, data_test2_params: "hepp"],
      picture_class: "avatar",
      img_class: "img-fluid"
    ]

    assigns = %{user: user, opts: opts}

    comp = ~H"""
    <.picture src={@user.avatar} opts={@opts} />
    """

    doc =
      comp
      |> rendered_to_string()
      |> Floki.parse_document!()

    [source_mq, source_jpeg] = Floki.find(doc, "source")

    assert source_mq
           |> assert_attr("media", ["(min-width: 0px) and (max-width: 760px)"])
           |> assert_attr("srcset", ["/media/images/avatars/mobile/27i97a.jpeg 700w"])

    assert source_jpeg
           |> assert_attr("type", ["image/jpeg"])
           |> assert_attr("srcset", [
             "/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w"
           ])

    assert doc
           |> Floki.find("picture")
           |> assert_attr("data-test-params", ["hepp"])
           |> assert_attr("data-test", ["data-test"])
           |> assert_attr("data-orientation", ["landscape"])

    assert doc
           |> Floki.find("picture > img")
           |> assert_attr("data-test2-params", ["hepp"])
           |> assert_attr("data-test2", ["data-test2"])
           |> assert_attr("alt", ["hepp!"])

    assert doc
           |> Floki.find("noscript > img")
           |> assert_attr("alt", ["hepp!"])

    # width height srcsets

    srcset = {Brando.BlueprintTest.Project, :cover_cdn}

    project_cover_cdn = %Brando.Images.Image{
      alt: nil,
      cdn: false,
      config_target: "image:Brando.BlueprintTest.Project:cover_cdn",
      credits: nil,
      deleted_at: nil,
      dominant_color: "#080808",
      focal: %Brando.Images.Focal{x: 50, y: 50},
      formats: [:jpg],
      height: 2000,
      id: 30,
      inserted_at: ~N[2022-02-28 16:41:22],
      path: "projects/covers/1qn45539cgnh.png",
      sizes: %{
        "xlarge" => "projects/covers/xlarge/1qn45539cgnh.jpg",
        "crop_xlarge" => "projects/covers/crop_xlarge/1qn45539cgnh.jpg"
      },
      status: :processed,
      title: nil,
      updated_at: ~N[2022-02-28 16:41:24],
      width: 1000
    }

    opts = [
      srcset: srcset,
      prefix: media_url(),
      key: :xlarge,
      lazyload: true,
      picture_class: "avatar",
      img_class: "img-fluid"
    ]

    assigns = %{project_cover_cdn: project_cover_cdn, opts: opts}

    comp = ~H"""
    <.picture src={@project_cover_cdn} opts={@opts} />
    """

    doc =
      comp
      |> rendered_to_string()
      |> Floki.parse_document!()

    assert doc
           |> Floki.find("img")
           |> assert_attr("width", ["1000"])
           |> assert_attr("height", ["2000"])

    # with cropped srcset
    srcset = {Brando.BlueprintTest.Project, :cover_cdn, :cropped}

    opts = [
      srcset: srcset,
      prefix: media_url(),
      key: :xlarge,
      lazyload: true,
      picture_class: "avatar",
      img_class: "img-fluid"
    ]

    assigns = %{project_cover_cdn: project_cover_cdn, opts: opts}

    comp = ~H"""
    <.picture src={@project_cover_cdn} opts={@opts} />
    """

    doc =
      comp
      |> rendered_to_string()
      |> Floki.parse_document!()

    assert doc
           |> Floki.find("img")
           |> assert_attr("width", ["1000"])
           |> assert_attr("height", ["500"])

    srcset = "Brando.BlueprintTest.Project:cover_cdn.cropped"

    opts = [
      srcset: srcset,
      prefix: media_url(),
      key: :xlarge,
      lazyload: true,
      picture_class: "avatar",
      img_class: "img-fluid"
    ]

    assigns = %{project_cover_cdn: project_cover_cdn, opts: opts}

    comp = ~H"""
    <.picture src={@project_cover_cdn} opts={@opts} />
    """

    doc =
      comp
      |> rendered_to_string()
      |> Floki.parse_document!()

    assert doc
           |> Floki.find("img")
           |> assert_attr("width", ["1000"])
           |> assert_attr("height", ["500"])

    # with default cropped srcset!
    srcset = {Brando.BlueprintTest.Project, :cover}

    opts = [
      srcset: srcset,
      prefix: media_url(),
      key: :xlarge,
      lazyload: true,
      picture_class: "avatar",
      img_class: "img-fluid"
    ]

    assigns = %{project_cover: project_cover, opts: opts}

    comp = ~H"""
    <.picture src={@project_cover} opts={@opts} />
    """

    doc =
      comp
      |> rendered_to_string()
      |> Floki.parse_document!()

    assert doc
           |> Floki.find("img")
           |> assert_attr("width", ["1000"])
           |> assert_attr("height", ["1000"])
  end

  test "picture_tag falls back to original while image is unprocessed" do
    user = Factory.build(:user)
    avatar = %{user.avatar | sizes: %{}, status: :unprocessed}

    opts = [
      prefix: media_url(),
      key: :small,
      placeholder: :dominant_color_faded,
      lazyload: true
    ]

    assigns = %{avatar: avatar, opts: opts}

    comp = ~H"""
    <.picture src={@avatar} opts={@opts} />
    """

    doc =
      comp
      |> rendered_to_string()
      |> Floki.parse_document!()

    assert doc
           |> Floki.find("picture")
           |> assert_attr("data-ll-srcset", [])

    assert doc
           |> Floki.find("picture > img")
           |> assert_attr("data-ll-image", ["data-ll-image"])
           |> assert_attr("data-ll-srcset-image", [])
           |> assert_attr("data-src", ["/media/images/avatars/27i97a.jpeg"])
           |> assert_attr("src", [
             "data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%27300%27%20height%3D%27200%27%20style%3D%27background%3Argba%280%2C0%2C0%2C0%29%27%2F%3E"
           ])

    assert doc
           |> Floki.find("noscript > img")
           |> assert_attr("src", ["/media/images/avatars/27i97a.jpeg"])
  end

  test "svg_fallback" do
    assert Brando.HTML.Images.svg_fallback(%{}, nil, width: 200, height: 200) ==
             "data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%27200%27%20height%3D%27200%27%20style%3D%27background%3Argba%280%2C0%2C0%2C%29%27%2F%3E"
  end

  test "get_sizes" do
    assert Brando.HTML.Images.get_sizes(["(min-width: 36em) 33.3vw", "100vw"]) ==
             "(min-width: 36em) 33.3vw, 100vw"

    assert_raise ArgumentError, fn ->
      Brando.HTML.Images.get_sizes("(min-width: 36em) 33.3vw")
    end
  end

  test "get_srcset" do
    img_field = Factory.build(:image)
    img_cfg = Factory.build(:image_cfg)

    assert_raise ArgumentError, fn ->
      assert Brando.HTML.Images.get_srcset(img_field, img_cfg, [], :svg) == ""
    end

    srcset = [
      {"small", "300w"},
      {"medium", "500w"},
      {"large", "700w"}
    ]

    img_cfg = Factory.build(:image_cfg, srcset: srcset)

    assert Brando.HTML.Images.get_srcset(img_field, img_cfg, [], :svg) ==
             {false, "image/small/1.jpg 300w, image/medium/1.jpg 500w, image/large/1.jpg 700w"}

    assert Brando.HTML.Images.get_srcset(img_field, srcset, [], :svg) ==
             {false, "image/small/1.jpg 300w, image/medium/1.jpg 500w, image/large/1.jpg 700w"}
  end

  test "get_srcset escapes whitespace and commas in filenames" do
    srcset = [{"small", "300w"}, {"large", "700w"}]

    img_field =
      Factory.build(:image,
        path: "image/NTECH 12, Keynote.jpg",
        sizes: %{
          "small" => "image/small/NTECH 12, Keynote.jpg",
          "large" => "image/large/NTECH 12, Keynote.jpg"
        }
      )

    {false, rendered} = Brando.HTML.Images.get_srcset(img_field, srcset, [], :svg)

    assert rendered ==
             "image/small/NTECH%2012%2C%20Keynote.jpg 300w, image/large/NTECH%2012%2C%20Keynote.jpg 700w"

    # every candidate is still `url descriptor`, so the list stays parseable
    assert rendered
           |> String.split(", ")
           |> Enum.all?(&match?([_url, _descriptor], String.split(&1, " ")))
  end

  defmodule SrcsetAssets do
    @moduledoc false
    use Brando.Blueprint,
      application: "Brando",
      domain: "HTMLTest",
      schema: "SrcsetAssets",
      singular: "srcset_asset",
      plural: "srcset_assets",
      gettext_module: Brando.Gettext

    @sizes %{
      "small" => %{"size" => "300", "quality" => 65},
      "medium" => %{"size" => "500", "quality" => 65},
      "large" => %{"size" => "700", "quality" => 65}
    }

    @flat_srcset [{"small", "300w"}, {"medium", "500w"}, {"large", "700w"}]
    @keyed_srcset %{default: [{"small", "300w"}, {"large", "700w"}]}

    assets do
      asset :cover, :image, cfg: [sizes: @sizes, srcset: @flat_srcset]
      asset :photos, :gallery, cfg: [sizes: @sizes, srcset: @flat_srcset]
      asset :keyed_cover, :image, cfg: [sizes: @sizes, srcset: @keyed_srcset]
      asset :keyed_photos, :gallery, cfg: [sizes: @sizes, srcset: @keyed_srcset]
    end
  end

  # A `:gallery` asset's config is `%{image: ImageConfig, video: VideoConfig}`
  # rather than an image config, so reading `:srcset` straight off it raised.
  test "get_srcset reads a gallery asset's image config" do
    img_field = Factory.build(:image)
    expected = "image/small/1.jpg 300w, image/medium/1.jpg 500w, image/large/1.jpg 700w"

    assert Brando.HTML.Images.get_srcset(img_field, {SrcsetAssets, :cover}, [], :svg) ==
             {false, expected}

    assert Brando.HTML.Images.get_srcset(img_field, {SrcsetAssets, :photos}, [], :svg) ==
             {false, expected}
  end

  test "get_srcset reads a keyed srcset from a gallery asset's image config" do
    img_field = Factory.build(:image)
    expected = "image/small/1.jpg 300w, image/large/1.jpg 700w"

    assert Brando.HTML.Images.get_srcset(img_field, {SrcsetAssets, :keyed_cover, :default}, [], :svg) ==
             {false, expected}

    assert Brando.HTML.Images.get_srcset(img_field, {SrcsetAssets, :keyed_photos, :default}, [], :svg) ==
             {false, expected}
  end

  test "get_srcset accepts a gallery asset through the string form" do
    img_field = Factory.build(:image)

    assert Brando.HTML.Images.get_srcset(
             img_field,
             "#{inspect(SrcsetAssets)}:keyed_photos.default",
             [],
             :svg
           ) == {false, "image/small/1.jpg 300w, image/large/1.jpg 700w"}
  end

  test "init_js" do
    assigns = %{}

    comp = ~H"""
    <.init_js />
    """

    assert rendered_to_string(comp) ==
             "<script>(function(C){C.remove('no-js');C.add('js');C.add('moonwalk')})(document.documentElement.classList)</script>"
  end

  test "render_data" do
    # Was a bare `put_env` with no restore at all, which is worse than the
    # `put_env(key, nil)` shape elsewhere: `config/test.exs:48-49` configures
    # `Brando.Villain` with both `extra_blocks` and `parser`, and a whole-key
    # overwrite drops `extra_blocks` for every test that runs after this one.
    put_test_env(Brando.Villain, parser: Brando.Villain.ParserTest.Parser)
    conn = %{request_path: "/projects/all", path_params: %{"category_slug" => "all"}}

    module_params =
      Factory.params_for(:module, %{vars: [], refs: [], code: "{% ref refs.text %}"})

    module = Factory.insert(:module, module_params)

    entry = %{
      entry_blocks: [
        %{
          block: %{
            uid: "1asdf2asdf",
            module_id: module.id,
            type: :module,
            vars: [],
            refs: [
              %{
                name: "text",
                description: "text",
                uid: "asdfasdf",
                data: %Brando.Villain.Blocks.TextBlock{
                  data: %Brando.Villain.Blocks.TextBlock.Data{
                    type: "text",
                    text: "SOMETHING -> $__CONTENT__ <- ANYTHING"
                  }
                }
              }
            ]
          }
        }
      ]
    }

    assigns = %{conn: conn, entry: entry}

    comp = ~H"""
    <.render_data conn={@conn} entry={@entry}>
      HELLO WORLD
    </.render_data>
    """

    assert rendered_to_string(comp) ==
             "\n  <div class=\"text\">SOMETHING -> \n  \n  HELLO WORLD\n\n   <- ANYTHING</div>\n"

    entry2 = %{
      entry_blocks: [
        %{
          block: %{
            uid: "1asdf2asdf",
            module_id: module.id,
            type: :module,
            vars: [],
            refs: [
              %{
                name: "text",
                description: "text",
                uid: "asdfasdf",
                data: %Brando.Villain.Blocks.TextBlock{
                  data: %Brando.Villain.Blocks.TextBlock.Data{
                    type: "text",
                    text: "SOMETHING -><- ANYTHING"
                  }
                }
              }
            ]
          }
        }
      ]
    }

    assigns = %{conn: conn, entry: entry2}

    comp = ~H"""
    <.render_data conn={@conn} entry={@entry} />
    """

    assert rendered_to_string(comp) == "\n  <div class=\"text\">SOMETHING -><- ANYTHING</div>\n"
  end

  test "breakpoint_debug_tag" do
    assert render_component(&breakpoint_debug_tag/1, %{}) ==
             "<i class=\"dbg-breakpoints\">\n  \n  <div class=\"breakpoint\"></div>\n  <div class=\"user-agent\"></div>\n</i>"
  end

  test "grid_debug_tag" do
    assert render_component(&grid_debug_tag/1, %{})

    "<div class=\"dbg-grid\"><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b></div>"
  end
end

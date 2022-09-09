defmodule Brando.HTMLTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase
  use RouterHelper
  import Brando.HTML
  import Brando.Utils, only: [media_url: 0]
  import Phoenix.HTML, only: [safe_to_string: 1]
  import Phoenix.LiveViewTest
  import Phoenix.LiveView.Helpers
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
    code = "asdf123"

    html =
      code
      |> google_analytics
      |> safe_to_string

    assert html =~ "ga('create','#{code}','auto')"
  end

  test "truncate" do
    assert truncate("hello", 7) == "hello"
    assert truncate("hello", 2) == "hel..."
    assert truncate(5, 5) == 5
  end

  test "render_meta" do
    mock_conn = %Plug.Conn{assigns: %{language: "en"}, private: %{plug_session: %{}}}

    assigns = %{}

    comp = ~H"""
    <.render_meta conn={mock_conn} />
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

  test "video_tag" do
    opts = [
      width: 400,
      height: 300,
      opacity: 0.5,
      preload: true,
      cover: :svg,
      poster: "my_poster.jpg",
      autoplay: true
    ]

    assigns = %{}

    comp = ~H"""
    <.video video={"https://src.vid"} opts={opts} />
    """

    assert rendered_to_string(comp) ==
             "<div class=\"video-wrapper video-file\" data-smart-video style=\"--aspect-ratio: 0.75\">\n  \n  \n    \n         <div data-cover>\n           <img\n             width=\"400\"\n             height=\"300\"\n             src=\"data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%27400%27%20height%3D%27300%27%20style%3D%27background%3Argba%280%2C0%2C0%2C0.5%29%27%2F%3E\" />\n         </div>\n       \n  \n  \n  <video width=\"400\" height=\"300\" alt=\"\" tabindex=\"0\" role=\"presentation\" preload=\"auto\" autoplay muted loop playsinline data-video poster=\"my_poster.jpg\" style=\"--aspect-ratio-division: 400/300\" data-src=\"https://src.vid\"></video>\n  <noscript>\n    <video width=\"400\" height=\"300\" alt=\"\" tabindex=\"0\" role=\"presentation\" preload=\"metadata\" muted loop playsinline src=\"https://src.vid\"></video>\n  </noscript>\n</div>"
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

    assigns = %{}

    comp = ~H"""
    <.picture src={user.avatar} opts={opts} />
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

    comp = ~H"""
    <.picture src={Map.put(user.avatar, :formats, [:jpg, :webp])} opts={opts} />
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

    comp = ~H"""
    <.picture src={Map.put(user.avatar, :formats, [:jpg, :webp, :avif])} opts={opts} />
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

    comp = ~H"""
    <.picture src={user.avatar} opts={opts} />
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
      height: true,
      width: true,
      picture_class: "avatar",
      img_class: "img-fluid"
    ]

    comp = ~H"""
    <.picture src={user.avatar} opts={opts} />
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

    comp = ~H"""
    <.picture src={user.avatar} opts={opts} />
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

    comp = ~H"""
    <.picture src={user.avatar} opts={opts} />
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

    comp = ~H"""
    <.picture src={user.avatar} opts={opts} />
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

    comp = ~H"""
    <.picture src={Map.put(user.avatar, :formats, [:jpg, :webp])} opts={opts} />
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

    comp = ~H"""
    <.picture src={user.avatar} opts={opts} />
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

    comp = ~H"""
    <.picture src={user.avatar} opts={opts} />
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
    opts = [
      srcset: {Brando.BlueprintTest.Project, :cover, :cropped},
      prefix: media_url(),
      key: :small,
      picture_class: "avatar",
      img_class: "img-fluid",
      placeholder: :dominant_color,
      lazyload: true
    ]

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
      width: 2000
    }

    comp = ~H"""
    <.picture src={project_cover} opts={opts} />
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
           |> assert_attr("data-src", [
             "data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%272000%27%20height%3D%272000%27%20style%3D%27background%3Argba%280%2C0%2C0%2C0%29%27%2F%3E"
           ])
           |> assert_attr("src", [
             "data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%272000%27%20height%3D%272000%27%20style%3D%27background%3Argba%280%2C0%2C0%2C0%29%27%2F%3E"
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

    comp = ~H"""
    <.picture src={user.avatar} opts={opts} />
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

    comp = ~H"""
    <.picture src={user.avatar} opts={opts} />
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

  test "include_css" do
    assert include_css(%Plug.Conn{host: "localhost", scheme: "http"}) |> safe_to_string ==
             "<link href=\"/css/app.css\" rel=\"stylesheet\">"

    Application.put_env(:brando, :hmr, true)

    assert include_css(%Plug.Conn{host: "localhost", scheme: "http"}) |> safe_to_string ==
             "<link href=\"http://localhost:9999/css/app.css\" rel=\"stylesheet\">"

    Application.put_env(:brando, :hmr, false)
  end

  test "include_js" do
    assert include_js(%Plug.Conn{host: "localhost", scheme: "http"})
           |> Enum.map(&safe_to_string/1) ==
             [
               "<script type=\"module\">!function(e,t,n){!(\"noModule\"in(t=e.createElement(\"script\")))&&\"onbeforeload\"in t&&(n=!1,e.addEventListener(\"beforeload\",function(e){if(e.target===t)n=!0;else if(!e.target.hasAttribute(\"nomodule\")||!n)return;e.preventDefault()},!0),t.type=\"module\",t.src=\".\",e.head.appendChild(t),t.remove())}(document)\n</script>",
               "<script defer src=\"/js/app.js\" type=\"module\"></script>",
               "<script defer nomodule src=\"/js/app.legacy.js\"></script>"
             ]

    Application.put_env(:brando, :hmr, true)

    assert include_js(%Plug.Conn{host: "localhost", scheme: "http"}) |> safe_to_string ==
             "<script defer src=\"http://localhost:9999/js/app.js\"></script>"

    Application.put_env(:brando, :hmr, false)
  end

  test "init_js" do
    assigns = %{}

    comp = ~H"""
    <.init_js />
    """

    assert rendered_to_string(comp) ==
             "<script>(function(C){C.remove('no-js');C.add('js');C.add('moonwalk')})(document.documentElement.classList)</script>"
  end

  test "breakpoint_debug_tag" do
    assert render_component(&breakpoint_debug_tag/1, %{}) ==
             "<i class=\"dbg-breakpoints\">\n  \n  <div class=\"breakpoint\"></div>\n  <div class=\"user-agent\"></div>\n</i>"
  end

  test "grid_debug_tag" do
    assert render_component(&grid_debug_tag/1, %{})

    "<div class=\"dbg-grid\"><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b><b></b></div>"
  end

  test "render_classes" do
    assert render_classes(["test"]) == ["test"]
    assert render_classes([:test]) == ["test"]
    assert render_classes(["test", "test2"]) == ["test", "test2"]
    assert render_classes(["test", test2: false]) == ["test"]
    assert render_classes(["test", test2: nil]) == ["test"]
    assert render_classes(["test", test2: true]) == ["test", "test2"]
    assert render_classes(["test", test2: true, test2: false]) == ["test", "test2"]
    assert render_classes(["test", test2: true, test3: true]) == ["test", "test2", "test3"]
    assert render_classes(test2: true, test3: true) == ["test2", "test3"]
  end
end

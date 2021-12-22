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
             "<div class=\"video-wrapper\" data-smart-video style=\"--aspect-ratio: 0.75\">\n  \n  \n         <div data-cover>\n           <img\n             width=\"400\"\n             height=\"300\"\n             src=\"data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%27400%27%20height%3D%27300%27%20style%3D%27background%3Argba%280%2C0%2C0%2C0.5%29%27%2F%3E\" />\n         </div>\n       \n  <video width=\"400\" height=\"300\" alt=\"\" tabindex=\"0\" role=\"presentation\" preload=\"auto\" autoplay muted loop playsinline data-video poster=\"my_poster.jpg\" data-src=\"https://src.vid\"></video>\n  <noscript>\n    <video width=\"400\" height=\"300\" alt=\"\" tabindex=\"0\" role=\"presentation\" preload=\"metadata\" muted loop playsinline src=\"https://src.vid\"></video>\n  </noscript>\n</div>"
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

    assert rendered_to_string(comp) ==
             "\n  <figure data-orientation=\"landscape\">\n  <picture class=\"avatar\" data-orientation=\"landscape\">\n    \n    <source srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" type=\"image/jpeg\">\n    <img class=\"img-fluid\" src=\"/media/images/avatars/small/27i97a.jpeg\" srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\">\n    <noscript>\n  <img src=\"/media/images/avatars/small/27i97a.jpeg\">\n</noscript>\n  </picture>\n  \n</figure>\n"

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

    assert rendered_to_string(comp) ==
             "\n  <figure data-orientation=\"landscape\">\n  <picture class=\"avatar\" data-orientation=\"landscape\">\n    \n    <source srcset=\"/media/images/avatars/small/27i97a.webp 300w, /media/images/avatars/medium/27i97a.webp 500w, /media/images/avatars/large/27i97a.webp 700w\" type=\"image/webp\"><source srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" type=\"image/jpeg\">\n    <img class=\"img-fluid\" src=\"/media/images/avatars/small/27i97a.jpeg\" srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\">\n    <noscript>\n  <img src=\"/media/images/avatars/small/27i97a.jpeg\">\n</noscript>\n  </picture>\n  \n</figure>\n"

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

    assert rendered_to_string(comp) ==
             "\n  <figure data-orientation=\"landscape\">\n  <picture class=\"avatar\" data-orientation=\"landscape\">\n    \n    <source srcset=\"/media/images/avatars/small/27i97a.avif 300w, /media/images/avatars/medium/27i97a.avif 500w, /media/images/avatars/large/27i97a.avif 700w\" type=\"image/avif\"><source srcset=\"/media/images/avatars/small/27i97a.webp 300w, /media/images/avatars/medium/27i97a.webp 500w, /media/images/avatars/large/27i97a.webp 700w\" type=\"image/webp\"><source srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" type=\"image/jpeg\">\n    <img class=\"img-fluid\" src=\"/media/images/avatars/small/27i97a.jpeg\" srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\">\n    <noscript>\n  <img src=\"/media/images/avatars/small/27i97a.jpeg\">\n</noscript>\n  </picture>\n  \n</figure>\n"

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

    assert rendered_to_string(comp) ==
             "\n  <figure data-orientation=\"landscape\">\n  <picture class=\"avatar\" data-orientation=\"landscape\">\n    \n    <source srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" type=\"image/jpeg\">\n    <img class=\"img-fluid\" src=\"/media/images/avatars/small/27i97a.jpeg\" srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\">\n    <noscript>\n  <img src=\"/media/images/avatars/small/27i97a.jpeg\">\n</noscript>\n  </picture>\n  \n    <figcaption>Title!</figcaption>\n  \n</figure>\n"

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

    assert rendered_to_string(comp) ==
             "\n  <figure data-orientation=\"landscape\">\n  <picture class=\"avatar\" data-orientation=\"landscape\">\n    \n    <source srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" type=\"image/jpeg\">\n    <img class=\"img-fluid\" src=\"/media/images/avatars/small/27i97a.jpeg\" height=\"200\" width=\"300\" srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\">\n    <noscript>\n  <img src=\"/media/images/avatars/small/27i97a.jpeg\">\n</noscript>\n  </picture>\n  \n</figure>\n"

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

    assert rendered_to_string(comp) ==
             "\n  <figure data-orientation=\"landscape\">\n  <picture class=\"avatar\" data-orientation=\"landscape\">\n    \n    <source srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" type=\"image/jpeg\">\n    <img class=\"img-fluid\" src=\"/media/images/avatars/small/27i97a.jpeg\" height=\"200\" width=\"200\" srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\">\n    <noscript>\n  <img src=\"/media/images/avatars/small/27i97a.jpeg\">\n</noscript>\n  </picture>\n  \n</figure>\n"

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

    assert rendered_to_string(comp) ==
             "\n  <a href=\"/media/images/avatars/small/27i97a.jpeg\" data-lightbox=\"/media/images/avatars/small/27i97a.jpeg\">\n  \n    <figure data-orientation=\"landscape\">\n  <picture class=\"avatar\" data-orientation=\"landscape\">\n    \n    <source srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" type=\"image/jpeg\">\n    <img class=\"img-fluid\" src=\"/media/images/avatars/small/27i97a.jpeg\" height=\"200\" width=\"200\" srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\">\n    <noscript>\n  <img src=\"/media/images/avatars/small/27i97a.jpeg\">\n</noscript>\n  </picture>\n  \n</figure>\n  \n</a>\n"

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

    assert rendered_to_string(comp) ==
             "\n  <a href=\"/media/images/avatars/small/27i97a.jpeg\" data-srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" data-lightbox=\"/media/images/avatars/small/27i97a.jpeg\">\n  \n    <figure data-orientation=\"landscape\">\n  <picture class=\"avatar\" data-orientation=\"landscape\" data-ll-srcset>\n    \n    <source data-srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" type=\"image/jpeg\">\n    <img data-ll-srcset-image class=\"img-fluid\" data-src=\"/media/images/avatars/small/27i97a.jpeg\" src=\"data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%27300%27%20height%3D%27200%27%20style%3D%27background%3Argba%280%2C0%2C0%2C0.05%29%27%2F%3E\" height=\"200\" width=\"300\" data-srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" data-ll-placeholder>\n    <noscript>\n  <img src=\"/media/images/avatars/small/27i97a.jpeg\">\n</noscript>\n  </picture>\n  \n</figure>\n  \n</a>\n"

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

    assert rendered_to_string(comp) ==
             "\n  <a href=\"/media/images/avatars/small/27i97a.jpeg\" data-srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" data-lightbox=\"/media/images/avatars/small/27i97a.jpeg\">\n  \n    <figure data-orientation=\"landscape\">\n  <picture class=\"avatar\" data-orientation=\"landscape\" data-ll-srcset>\n    \n    <source data-srcset=\"/media/images/avatars/small/27i97a.webp 300w, /media/images/avatars/medium/27i97a.webp 500w, /media/images/avatars/large/27i97a.webp 700w\" type=\"image/webp\"><source data-srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" type=\"image/jpeg\">\n    <img data-ll-srcset-image class=\"img-fluid\" data-src=\"/media/images/avatars/small/27i97a.jpeg\" src=\"data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%27300%27%20height%3D%27200%27%20style%3D%27background%3Argba%280%2C0%2C0%2C0.05%29%27%2F%3E\" height=\"200\" width=\"300\" data-srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" data-ll-placeholder>\n    <noscript>\n  <img src=\"/media/images/avatars/small/27i97a.jpeg\">\n</noscript>\n  </picture>\n  \n</figure>\n  \n</a>\n"

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

    assert rendered_to_string(comp) ==
             "\n  <figure data-orientation=\"landscape\">\n  <picture class=\"avatar\" data-orientation=\"landscape\" data-ll-srcset>\n    \n    <source data-srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" srcset=\"/media/images/avatars/micro/27i97a.jpeg 300w, /media/images/avatars/micro/27i97a.jpeg 500w, /media/images/avatars/micro/27i97a.jpeg 700w\" type=\"image/jpeg\">\n    <img data-ll-srcset-image class=\"img-fluid\" data-src=\"/media/images/avatars/small/27i97a.jpeg\" src=\"/media/images/avatars/micro/27i97a.jpeg\" height=\"200\" width=\"300\" data-srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" data-ll-placeholder srcset=\"/media/images/avatars/micro/27i97a.jpeg 300w, /media/images/avatars/micro/27i97a.jpeg 500w, /media/images/avatars/micro/27i97a.jpeg 700w\">\n    <noscript>\n  <img src=\"/media/images/avatars/small/27i97a.jpeg\">\n</noscript>\n  </picture>\n  \n</figure>\n"

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

    assert rendered_to_string(comp) ==
             "\n  <figure data-orientation=\"landscape\">\n  <picture class=\"avatar\" data-orientation=\"landscape\" data-ll-srcset>\n    \n    <source data-srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" type=\"image/jpeg\">\n    <img data-ll-srcset-image class=\"img-fluid\" data-src=\"/media/images/avatars/small/27i97a.jpeg\" src=\"data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%27300%27%20height%3D%27200%27%20style%3D%27background%3Argba%280%2C0%2C0%2C0.05%29%27%2F%3E\" height=\"200\" width=\"300\" data-srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" data-ll-placeholder>\n    <noscript>\n  <img src=\"/media/images/avatars/small/27i97a.jpeg\">\n</noscript>\n  </picture>\n  \n</figure>\n"

    # ---
    opts = [
      srcset: srcset,
      prefix: media_url(),
      key: :small,
      picture_class: "avatar",
      img_class: "img-fluid",
      placeholder: :dominant_color,
      lazyload: true
    ]

    comp = ~H"""
    <.picture src={user.avatar} opts={opts} />
    """

    assert rendered_to_string(comp) ==
             "\n  <figure data-placeholder=\"dominant_color\" data-orientation=\"landscape\">\n  <picture class=\"avatar\" style=\"background-color: #deadb33f\" data-orientation=\"landscape\" data-ll-srcset>\n    \n    <source data-srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" type=\"image/jpeg\">\n    <img data-ll-srcset-image class=\"img-fluid\" data-src=\"/media/images/avatars/small/27i97a.jpeg\" src=\"data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%27300%27%20height%3D%27200%27%20style%3D%27background%3Argba%280%2C0%2C0%2C0%29%27%2F%3E\" height=\"200\" width=\"300\" data-srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" data-ll-placeholder>\n    <noscript>\n  <img src=\"/media/images/avatars/small/27i97a.jpeg\">\n</noscript>\n  </picture>\n  \n</figure>\n"

    # ---
    opts = [
      srcset: srcset,
      prefix: media_url(),
      key: :small,
      picture_class: "avatar",
      img_class: "img-fluid",
      lazyload: true
    ]

    comp = ~H"""
    <.picture src={user.avatar} opts={opts} />
    """

    assert rendered_to_string(comp) ==
             "\n  <figure data-orientation=\"landscape\">\n  <picture class=\"avatar\" data-orientation=\"landscape\" data-ll-srcset>\n    \n    <source data-srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" type=\"image/jpeg\">\n    <img data-ll-srcset-image class=\"img-fluid\" data-src=\"/media/images/avatars/small/27i97a.jpeg\" height=\"200\" width=\"300\" data-srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" data-ll-placeholder>\n    <noscript>\n  <img src=\"/media/images/avatars/small/27i97a.jpeg\">\n</noscript>\n  </picture>\n  \n</figure>\n"

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

    assert rendered_to_string(comp) ==
             "\n  <figure data-orientation=\"landscape\">\n  <picture class=\"avatar\" data-orientation=\"landscape\">\n    <source media=\"(min-width: 0px) and (max-width: 760px)\" srcset=\"/media/images/avatars/mobile/27i97a.jpeg 700w\">\n    <source srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" type=\"image/jpeg\">\n    <img class=\"img-fluid\" src=\"/media/images/avatars/small/27i97a.jpeg\" srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\">\n    <noscript>\n  <img src=\"/media/images/avatars/small/27i97a.jpeg\">\n</noscript>\n  </picture>\n  \n</figure>\n"

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

    assert rendered_to_string(comp) ==
             "\n  <figure data-orientation=\"landscape\">\n  <picture class=\"avatar\" data-test-params=\"hepp\" data-test data-orientation=\"landscape\">\n    <source media=\"(min-width: 0px) and (max-width: 760px)\" srcset=\"/media/images/avatars/mobile/27i97a.jpeg 700w\">\n    <source srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" type=\"image/jpeg\">\n    <img class=\"img-fluid\" data-test2-params=\"hepp\" data-test2 src=\"/media/images/avatars/small/27i97a.jpeg\" srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" alt=\"hepp!\">\n    <noscript>\n  <img alt=\"hepp!\" src=\"/media/images/avatars/small/27i97a.jpeg\">\n</noscript>\n  </picture>\n  \n</figure>\n"

    # ---
    opts = [
      key: :small,
      prefix: media_url(),
      picture_class: "avatar",
      img_class: "img-fluid"
    ]

    comp = ~H"""
    <.picture src={user.avatar} opts={opts} />
    """

    assert rendered_to_string(comp) ==
             "\n  <figure data-orientation=\"landscape\">\n  <picture class=\"avatar\" data-orientation=\"landscape\">\n    \n    \n    <img class=\"img-fluid\" src=\"/media/images/avatars/small/27i97a.jpeg\">\n    <noscript>\n  <img src=\"/media/images/avatars/small/27i97a.jpeg\">\n</noscript>\n  </picture>\n  \n</figure>\n"
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
end

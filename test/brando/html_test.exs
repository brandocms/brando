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
    assigns = %{
      __changed__: %{}
    }

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
    assigns = %{__changed__: %{}}

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

    assigns = %{__changed__: %{}}

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

    assigns = %{
      __changed__: %{}
    }

    comp = ~H"""
    <.video_tag video={"https://src.vid"} opts={opts} />
    """

    assert rendered_to_string(comp) ==
             "<div class=\"video-wrapper\" data-smart-video style=\"--aspect-ratio: 0.75\">\n  \n  \n         <div data-cover>\n           <img\n             width=\"400\"\n             height=\"300\"\n             src=\"data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%27400%27%20height%3D%27300%27%20style%3D%27background%3Argba%280%2C0%2C0%2C0.5%29%27%2F%3E\" />\n         </div>\n       \n  <video width=\"400\" height=\"300\" alt=\"\" tabindex=\"0\" role=\"presentation\" preload=\"auto\" autoplay muted loop playsinline data-video poster=\"my_poster.jpg\" data-src=\"https://src.vid\"></video>\n  <noscript>\n    <video width=\"400\" height=\"300\" alt=\"\" tabindex=\"0\" role=\"presentation\" preload=\"metadata\" muted loop playsinline src=\"https://src.vid\"></video>\n  </noscript>\n</div>"
  end

  test "img_tag" do
    user = Factory.build(:user)

    assert img_tag(user.avatar, :medium) |> safe_to_string ==
             "<img src=\"images/avatars/medium/27i97a.jpeg\">"

    assert img_tag(user.avatar, :medium, prefix: media_url()) |> safe_to_string ==
             "<img src=\"/media/images/avatars/medium/27i97a.jpeg\">"

    assert img_tag(nil, :medium, default: "test.jpg") |> safe_to_string ==
             "<img src=\"test.jpg\">"

    assert img_tag(user.avatar, :medium, prefix: media_url(), srcset: {Brando.Users.User, :avatar})
           |> safe_to_string ==
             "<img src=\"data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%27300%27%20height%3D%27200%27%20style%3D%27background%3Argba%280%2C0%2C0%2C0%29%27%2F%3E\" srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\">"
  end

  test "picture_tag" do
    user = Factory.build(:user)
    srcset = {Brando.Users.User, :avatar}

    assert picture_tag(
             user.avatar,
             srcset: srcset,
             prefix: media_url(),
             key: :small,
             picture_class: "avatar",
             img_class: "img-fluid"
           )
           |> safe_to_string ==
             "<picture class=\"avatar\" data-orientation=\"landscape\"><source srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" type=\"image/jpeg\"><img class=\"img-fluid\" src=\"/media/images/avatars/small/27i97a.jpeg\" srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\"><noscript><img src=\"/media/images/avatars/small/27i97a.jpeg\"></noscript></picture>"

    assert picture_tag(
             Map.put(user.avatar, :formats, [:jpg, :webp]),
             srcset: srcset,
             prefix: media_url(),
             key: :small,
             picture_class: "avatar",
             img_class: "img-fluid"
           )
           |> safe_to_string ==
             "<picture class=\"avatar\" data-orientation=\"landscape\"><source srcset=\"/media/images/avatars/small/27i97a.webp 300w, /media/images/avatars/medium/27i97a.webp 500w, /media/images/avatars/large/27i97a.webp 700w\" type=\"image/webp\"><source srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" type=\"image/jpeg\"><img class=\"img-fluid\" src=\"/media/images/avatars/small/27i97a.jpeg\" srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\"><noscript><img src=\"/media/images/avatars/small/27i97a.jpeg\"></noscript></picture>"

    assert picture_tag(
             Map.put(user.avatar, :formats, [:jpg, :webp, :avif]),
             srcset: srcset,
             prefix: media_url(),
             key: :small,
             picture_class: "avatar",
             img_class: "img-fluid"
           )
           |> safe_to_string ==
             "<picture class=\"avatar\" data-orientation=\"landscape\"><source srcset=\"/media/images/avatars/small/27i97a.avif 300w, /media/images/avatars/medium/27i97a.avif 500w, /media/images/avatars/large/27i97a.avif 700w\" type=\"image/avif\"><source srcset=\"/media/images/avatars/small/27i97a.webp 300w, /media/images/avatars/medium/27i97a.webp 500w, /media/images/avatars/large/27i97a.webp 700w\" type=\"image/webp\"><source srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" type=\"image/jpeg\"><img class=\"img-fluid\" src=\"/media/images/avatars/small/27i97a.jpeg\" srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\"><noscript><img src=\"/media/images/avatars/small/27i97a.jpeg\"></noscript></picture>"

    assert picture_tag(
             user.avatar,
             srcset: srcset,
             prefix: media_url(),
             key: :small,
             caption: true,
             picture_class: "avatar",
             img_class: "img-fluid"
           )
           |> safe_to_string ==
             "<picture class=\"avatar\" data-orientation=\"landscape\"><source srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" type=\"image/jpeg\"><img class=\"img-fluid\" src=\"/media/images/avatars/small/27i97a.jpeg\" srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\"><figcaption>Title!</figcaption><noscript><img src=\"/media/images/avatars/small/27i97a.jpeg\"></noscript></picture>"

    assert picture_tag(
             user.avatar,
             srcset: srcset,
             prefix: media_url(),
             key: :small,
             height: true,
             width: true,
             picture_class: "avatar",
             img_class: "img-fluid"
           )
           |> safe_to_string ==
             "<picture class=\"avatar\" data-orientation=\"landscape\"><source srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" type=\"image/jpeg\"><img class=\"img-fluid\" height=\"200\" src=\"/media/images/avatars/small/27i97a.jpeg\" srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" width=\"300\"><noscript><img src=\"/media/images/avatars/small/27i97a.jpeg\"></noscript></picture>"

    assert picture_tag(
             user.avatar,
             srcset: srcset,
             prefix: media_url(),
             key: :small,
             height: 200,
             width: 200,
             picture_class: "avatar",
             img_class: "img-fluid"
           )
           |> safe_to_string ==
             "<picture class=\"avatar\" data-orientation=\"landscape\"><source srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" type=\"image/jpeg\"><img class=\"img-fluid\" height=\"200\" src=\"/media/images/avatars/small/27i97a.jpeg\" srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" width=\"200\"><noscript><img src=\"/media/images/avatars/small/27i97a.jpeg\"></noscript></picture>"

    assert picture_tag(
             user.avatar,
             lightbox: true,
             srcset: srcset,
             prefix: media_url(),
             key: :small,
             height: 200,
             width: 200,
             picture_class: "avatar",
             img_class: "img-fluid"
           )
           |> safe_to_string ==
             "<a data-lightbox=\"/media/images/avatars/small/27i97a.jpeg\" href=\"/media/images/avatars/small/27i97a.jpeg\"><picture class=\"avatar\" data-orientation=\"landscape\"><source srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" type=\"image/jpeg\"><img class=\"img-fluid\" height=\"200\" src=\"/media/images/avatars/small/27i97a.jpeg\" srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" width=\"200\"><noscript><img src=\"/media/images/avatars/small/27i97a.jpeg\"></noscript></picture></a>"

    assert picture_tag(
             user.avatar,
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
           )
           |> safe_to_string ==
             "<a data-lightbox=\"/media/images/avatars/small/27i97a.jpeg\" data-srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" href=\"/media/images/avatars/small/27i97a.jpeg\"><picture class=\"avatar\" data-ll-srcset data-orientation=\"landscape\"><source data-srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" type=\"image/jpeg\"><img class=\"img-fluid\" data-ll-placeholder data-ll-srcset-image data-src=\"/media/images/avatars/small/27i97a.jpeg\" data-srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" height=\"200\" src=\"data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%27300%27%20height%3D%27200%27%20style%3D%27background%3Argba%280%2C0%2C0%2C0.05%29%27%2F%3E\" width=\"300\"><noscript><img src=\"/media/images/avatars/small/27i97a.jpeg\"></noscript></picture></a>"

    assert picture_tag(
             Map.put(user.avatar, :formats, [:jpg, :webp]),
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
           )
           |> safe_to_string ==
             "<a data-lightbox=\"/media/images/avatars/small/27i97a.jpeg\" data-srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" href=\"/media/images/avatars/small/27i97a.jpeg\"><picture class=\"avatar\" data-ll-srcset data-orientation=\"landscape\"><source data-srcset=\"/media/images/avatars/small/27i97a.webp 300w, /media/images/avatars/medium/27i97a.webp 500w, /media/images/avatars/large/27i97a.webp 700w\" type=\"image/webp\"><source data-srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" type=\"image/jpeg\"><img class=\"img-fluid\" data-ll-placeholder data-ll-srcset-image data-src=\"/media/images/avatars/small/27i97a.jpeg\" data-srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" height=\"200\" src=\"data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%27300%27%20height%3D%27200%27%20style%3D%27background%3Argba%280%2C0%2C0%2C0.05%29%27%2F%3E\" width=\"300\"><noscript><img src=\"/media/images/avatars/small/27i97a.jpeg\"></noscript></picture></a>"

    assert picture_tag(
             user.avatar,
             srcset: srcset,
             prefix: media_url(),
             key: :small,
             picture_class: "avatar",
             img_class: "img-fluid",
             lazyload: true,
             placeholder: :micro
           )
           |> safe_to_string ==
             "<picture class=\"avatar\" data-ll-srcset data-orientation=\"landscape\"><source data-srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" srcset=\"/media/images/avatars/micro/27i97a.jpeg 300w, /media/images/avatars/micro/27i97a.jpeg 500w, /media/images/avatars/micro/27i97a.jpeg 700w\" type=\"image/jpeg\"><img class=\"img-fluid\" data-ll-placeholder data-ll-srcset-image data-src=\"/media/images/avatars/small/27i97a.jpeg\" data-srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" height=\"200\" src=\"/media/images/avatars/micro/27i97a.jpeg\" srcset=\"/media/images/avatars/micro/27i97a.jpeg 300w, /media/images/avatars/micro/27i97a.jpeg 500w, /media/images/avatars/micro/27i97a.jpeg 700w\" width=\"300\"><noscript><img src=\"/media/images/avatars/small/27i97a.jpeg\"></noscript></picture>"

    assert picture_tag(
             user.avatar,
             srcset: srcset,
             prefix: media_url(),
             key: :small,
             picture_class: "avatar",
             img_class: "img-fluid",
             placeholder: :svg,
             lazyload: true
           )
           |> safe_to_string ==
             "<picture class=\"avatar\" data-ll-srcset data-orientation=\"landscape\"><source data-srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" type=\"image/jpeg\"><img class=\"img-fluid\" data-ll-placeholder data-ll-srcset-image data-src=\"/media/images/avatars/small/27i97a.jpeg\" data-srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" height=\"200\" src=\"data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%27300%27%20height%3D%27200%27%20style%3D%27background%3Argba%280%2C0%2C0%2C0.05%29%27%2F%3E\" width=\"300\"><noscript><img src=\"/media/images/avatars/small/27i97a.jpeg\"></noscript></picture>"

    assert picture_tag(
             user.avatar,
             srcset: srcset,
             prefix: media_url(),
             key: :small,
             picture_class: "avatar",
             img_class: "img-fluid",
             placeholder: :dominant_color,
             lazyload: true
           )
           |> safe_to_string ==
             "<picture class=\"avatar\" data-ll-srcset data-orientation=\"landscape\" style=\"background-color: #deadb33f\"><source data-srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" type=\"image/jpeg\"><img class=\"img-fluid\" data-ll-placeholder data-ll-srcset-image data-src=\"/media/images/avatars/small/27i97a.jpeg\" data-srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" height=\"200\" src=\"data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%27300%27%20height%3D%27200%27%20style%3D%27background%3Argba%280%2C0%2C0%2C0%29%27%2F%3E\" width=\"300\"><noscript><img src=\"/media/images/avatars/small/27i97a.jpeg\"></noscript></picture>"

    assert picture_tag(
             user.avatar,
             srcset: srcset,
             prefix: media_url(),
             key: :small,
             picture_class: "avatar",
             img_class: "img-fluid",
             lazyload: true
           )
           |> safe_to_string ==
             "<picture class=\"avatar\" data-ll-srcset data-orientation=\"landscape\"><source data-srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" type=\"image/jpeg\"><img class=\"img-fluid\" data-ll-placeholder data-ll-srcset-image data-src=\"/media/images/avatars/small/27i97a.jpeg\" data-srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" height=\"200\" width=\"300\"><noscript><img src=\"/media/images/avatars/small/27i97a.jpeg\"></noscript></picture>"

    media_queries = [
      {"(min-width: 0px) and (max-width: 760px)", [{"mobile", "700w"}]}
    ]

    assert picture_tag(
             user.avatar,
             srcset: srcset,
             media_queries: media_queries,
             prefix: media_url(),
             key: :small,
             picture_class: "avatar",
             img_class: "img-fluid"
           )
           |> safe_to_string ==
             "<picture class=\"avatar\" data-orientation=\"landscape\"><source media=\"(min-width: 0px) and (max-width: 760px)\" srcset=\"/media/images/avatars/mobile/27i97a.jpeg 700w\"><source srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" type=\"image/jpeg\"><img class=\"img-fluid\" src=\"/media/images/avatars/small/27i97a.jpeg\" srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\"><noscript><img src=\"/media/images/avatars/small/27i97a.jpeg\"></noscript></picture>"

    assert picture_tag(
             user.avatar,
             alt: "hepp!",
             srcset: srcset,
             media_queries: media_queries,
             prefix: media_url(),
             key: :small,
             picture_attrs: [data_test: true, data_test_params: "hepp"],
             img_attrs: [data_test2: true, data_test2_params: "hepp"],
             picture_class: "avatar",
             img_class: "img-fluid"
           )
           |> safe_to_string ==
             "<picture class=\"avatar\" data-orientation=\"landscape\" data-test data-test-params=\"hepp\"><source media=\"(min-width: 0px) and (max-width: 760px)\" srcset=\"/media/images/avatars/mobile/27i97a.jpeg 700w\"><source srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\" type=\"image/jpeg\"><img alt=\"hepp!\" class=\"img-fluid\" data-test2 data-test2-params=\"hepp\" src=\"/media/images/avatars/small/27i97a.jpeg\" srcset=\"/media/images/avatars/small/27i97a.jpeg 300w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/large/27i97a.jpeg 700w\"><noscript><img alt=\"hepp!\" src=\"/media/images/avatars/small/27i97a.jpeg\"></noscript></picture>"

    assert picture_tag(
             user.avatar,
             key: :small,
             prefix: media_url(),
             picture_class: "avatar",
             img_class: "img-fluid"
           )
           |> safe_to_string ==
             "<picture class=\"avatar\" data-orientation=\"landscape\"><img class=\"img-fluid\" src=\"/media/images/avatars/small/27i97a.jpeg\"><noscript><img src=\"/media/images/avatars/small/27i97a.jpeg\"></noscript></picture>"
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
    assigns = %{__changed__: %{}}

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

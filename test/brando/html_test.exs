defmodule Brando.HTMLTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase
  use RouterHelper
  import Brando.HTML
  import Brando.Utils, only: [media_url: 0]
  import Phoenix.HTML, only: [safe_to_string: 1]
  alias Brando.Factory

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

  test "check_or_x/1" do
    assert check_or_x(false) == "<i class=\"icon-centered fa fa-times text-danger\"></i>"
    assert check_or_x(nil) == "<i class=\"icon-centered fa fa-times text-danger\"></i>"
    assert check_or_x(true) == "<i class=\"icon-centered fa fa-check text-success\"></i>"
  end

  test "body_tag" do
    mock_conn = %{private: %{brando_css_classes: "one two three"}}

    html =
      mock_conn
      |> body_tag
      |> safe_to_string()

    assert html == ~s(<body class="one two three unloaded" data-vsn=\"#{Brando.version()}\">)

    mock_conn = %{
      private: %{
        brando_css_classes: "one two three",
        brando_section_name: "some-section"
      }
    }

    html =
      mock_conn
      |> body_tag
      |> safe_to_string

    assert html ==
             "<body class=\"one two three unloaded\" data-script=\"some-section\" data-vsn=\"#{
               Brando.version()
             }\">"

    html =
      mock_conn
      |> body_tag(id: "test")
      |> safe_to_string

    assert html ==
             "<body class=\"one two three unloaded\" data-script=\"some-section\" data-vsn=\"#{
               Brando.version()
             }\" id=\"test\">"
  end

  test "cookie_law" do
    mock_conn = %{cookies: %{}}
    html = cookie_law(mock_conn, "Accept cookielaw") |> Phoenix.HTML.safe_to_string()
    assert html =~ "<p>Accept cookielaw</p>"
    assert html =~ "OK"
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

  test "meta_tag" do
    assert meta_tag("keywords", "hello, world") ==
             {:safe,
              [
                60,
                "meta",
                [
                  [32, "content", 61, 34, "hello, world", 34],
                  [32, "name", 61, 34, "keywords", 34]
                ],
                62
              ]}

    assert meta_tag({"keywords", "hello, world"}) ==
             {:safe,
              [
                60,
                "meta",
                [
                  [32, "content", 61, 34, "hello, world", 34],
                  [32, "name", 61, 34, "keywords", 34]
                ],
                62
              ]}
  end

  test "render_meta" do
    mock_conn = %Plug.Conn{private: %{plug_session: %{}}}

    html =
      mock_conn
      |> render_meta()
      |> safe_to_string()

    assert html =~ ~s(<meta content="MyApp" property="og:site_name">)
    assert html =~ ~s(<meta content="Firma | Velkommen!" property="og:title">)
    assert html =~ ~s(<meta content="Firma | Velkommen!" name="title">)
    assert html =~ ~s(<meta content="http://localhost" property="og:url">)
  end

  test "active/2" do
    conn = build_conn(:get, "/some/link")
    assert active(conn, "/some/link") == "active"
    assert active(conn, "/some/other/link") == ""
  end

  test "img_tag" do
    user = Factory.build(:user)

    assert img_tag(user.avatar, :medium) |> safe_to_string ==
             "<img src=\"images/avatars/medium/27i97a.jpeg\">"

    assert img_tag(user.avatar, :medium, prefix: media_url()) |> safe_to_string ==
             "<img src=\"/media/images/avatars/medium/27i97a.jpeg\">"

    assert img_tag(nil, :medium, default: "test.jpg") |> safe_to_string ==
             "<img src=\"medium/test.jpg\">"

    assert img_tag(user.avatar, :medium, prefix: media_url(), srcset: {Brando.Users.User, :avatar})
           |> safe_to_string ==
             "<img src=\"data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%27%27%20height%3D%27%27%20style%3D%27background%3Argba%280%2C0%2C0%2C0%29%27%2F%3E\" srcset=\"/media/images/avatars/large/27i97a.jpeg 700w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/small/27i97a.jpeg 300w\">"
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
             "<picture class=\"avatar\" data-orientation=\"portrait\"><source srcset=\"/media/images/avatars/large/27i97a.jpeg 700w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/small/27i97a.jpeg 300w\"><img class=\"img-fluid\" src=\"/media/images/avatars/small/27i97a.jpeg\" srcset=\"/media/images/avatars/large/27i97a.jpeg 700w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/small/27i97a.jpeg 300w\"><noscript><img src=\"/media/images/avatars/small/27i97a.jpeg\"></noscript></picture>"

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
             "<picture class=\"avatar\" data-orientation=\"portrait\" data-ll-srcset><source data-srcset=\"/media/images/avatars/large/27i97a.jpeg 700w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/small/27i97a.jpeg 300w\" srcset=\"/media/images/avatars/micro/27i97a.jpeg 700w, /media/images/avatars/micro/27i97a.jpeg 500w, /media/images/avatars/micro/27i97a.jpeg 300w\"><img class=\"img-fluid\" data-src=\"/media/images/avatars/small/27i97a.jpeg\" data-srcset=\"/media/images/avatars/large/27i97a.jpeg 700w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/small/27i97a.jpeg 300w\" src=\"/media/images/avatars/micro/27i97a.jpeg\" srcset=\"/media/images/avatars/micro/27i97a.jpeg 700w, /media/images/avatars/micro/27i97a.jpeg 500w, /media/images/avatars/micro/27i97a.jpeg 300w\" data-ll-placeholder><noscript><img src=\"/media/images/avatars/small/27i97a.jpeg\"></noscript></picture>"

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
             "<picture class=\"avatar\" data-orientation=\"portrait\" data-ll-srcset><source data-srcset=\"/media/images/avatars/large/27i97a.jpeg 700w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/small/27i97a.jpeg 300w\"><img class=\"img-fluid\" data-src=\"/media/images/avatars/small/27i97a.jpeg\" data-srcset=\"/media/images/avatars/large/27i97a.jpeg 700w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/small/27i97a.jpeg 300w\" src=\"data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%27%27%20height%3D%27%27%20style%3D%27background%3Argba%280%2C0%2C0%2C0.05%29%27%2F%3E\" data-ll-placeholder><noscript><img src=\"/media/images/avatars/small/27i97a.jpeg\"></noscript></picture>"

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
             "<picture class=\"avatar\" data-orientation=\"portrait\" data-ll-srcset><source data-srcset=\"/media/images/avatars/large/27i97a.jpeg 700w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/small/27i97a.jpeg 300w\"><img class=\"img-fluid\" data-src=\"/media/images/avatars/small/27i97a.jpeg\" data-srcset=\"/media/images/avatars/large/27i97a.jpeg 700w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/small/27i97a.jpeg 300w\" data-ll-placeholder><noscript><img src=\"/media/images/avatars/small/27i97a.jpeg\"></noscript></picture>"

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
             "<picture class=\"avatar\" data-orientation=\"portrait\"><source media=\"(min-width: 0px) and (max-width: 760px)\" srcset=\"/media/images/avatars/mobile/27i97a.jpeg 700w\"><source srcset=\"/media/images/avatars/large/27i97a.jpeg 700w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/small/27i97a.jpeg 300w\"><img class=\"img-fluid\" src=\"/media/images/avatars/small/27i97a.jpeg\" srcset=\"/media/images/avatars/large/27i97a.jpeg 700w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/small/27i97a.jpeg 300w\"><noscript><img src=\"/media/images/avatars/small/27i97a.jpeg\"></noscript></picture>"

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
             "<picture class=\"avatar\" data-orientation=\"portrait\" data-test-params=\"hepp\" data-test><source media=\"(min-width: 0px) and (max-width: 760px)\" srcset=\"/media/images/avatars/mobile/27i97a.jpeg 700w\"><source srcset=\"/media/images/avatars/large/27i97a.jpeg 700w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/small/27i97a.jpeg 300w\"><img alt=\"hepp!\" class=\"img-fluid\" data-test2-params=\"hepp\" src=\"/media/images/avatars/small/27i97a.jpeg\" srcset=\"/media/images/avatars/large/27i97a.jpeg 700w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/small/27i97a.jpeg 300w\" data-test2><noscript><img src=\"/media/images/avatars/small/27i97a.jpeg\"></noscript></picture>"
  end
end

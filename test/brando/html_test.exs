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
    assert body_tag(mock_conn)
           == {:safe, ~s(<body class="one two three unloaded">)}

    mock_conn = %{private: %{brando_css_classes: "one two three", brando_section_name: "some-section"}}
    assert body_tag(mock_conn)
           == {:safe, ~s(<body id="toppen" data-script="some-section" class="one two three unloaded">)}
  end

  test "cookie_law" do
    mock_conn = %{cookies: %{"cookielaw_accepted" => "1"}}
    assert cookie_law(mock_conn, "Accept cookielaw") == nil

    mock_conn = %{cookies: %{}}
    {:safe, html} = cookie_law(mock_conn, "Accept cookielaw")
    assert html =~ "<p>Accept cookielaw</p>"
    assert html =~ "OK"
  end

  test "google_analytics" do
    code = "asdf123"
    {:safe, html} = google_analytics(code)
    assert html =~ "ga('create','#{code}','auto')"
  end

  test "status_indicators" do
    {:safe, html} = status_indicators()
    assert html =~ "status-published"
    assert html =~ "Published"
  end

  test "truncate" do
    assert truncate("hello", 7) == "hello"
    assert truncate("hello", 2) == "hel..."
    assert truncate(5, 5) == 5
  end

  test "meta_tag" do
    assert meta_tag("keywords", "hello, world") ==
           {:safe, [60, "meta", [[32, "content", 61, 34, "hello, world", 34], [32, "property", 61, 34, "keywords", 34]], 62]}
    assert meta_tag({"keywords", "hello, world"}) ==
           {:safe, [60, "meta", [[32, "content", 61, 34, "hello, world", 34], [32, "property", 61, 34, "keywords", 34]], 62]}
  end

  test "render_meta" do
    mock_conn = %Plug.Conn{private: %{plug_session: %{}}}
    {:safe, html} = render_meta(mock_conn)
    assert html =~ ~s(<meta content="MyApp" property="og:site_name">)
    assert html =~ ~s(<meta content="MyApp" property="og:title">)
    assert html =~ ~s(<meta content="http://localhost" property="og:url">)
  end

  test "active/2" do
    conn = build_conn(:get, "/some/link")
    assert active(conn, "/some/link") == "active"
    assert active(conn, "/some/other/link") == ""
  end

  test "img_tag" do
    user = Factory.insert(:user)

    assert img_tag(user.avatar, :medium) |> safe_to_string
           == "<img src=\"images/avatars/medium/27i97a.jpeg\">"

    assert img_tag(user.avatar, :medium, prefix: media_url()) |> safe_to_string
           == "<img src=\"/media/images/avatars/medium/27i97a.jpeg\">"

    assert img_tag(nil, :medium, default: "test.jpg") |> safe_to_string
           == "<img src=\"medium/test.jpg\">"

    assert img_tag(user.avatar, :medium, prefix: media_url(), srcset: {Brando.User, :avatar}) |> safe_to_string
           == "<img src=\"data:image/svg+xml;charset=utf-8,%3Csvg%20xmlns%3D%27http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%27%20width%3D%27%27%20height%3D%27%27%20style%3D%27background%3Atransparent%27%2F%3E\" srcset=\"/media/images/avatars/large/27i97a.jpeg 700w, /media/images/avatars/medium/27i97a.jpeg 500w, /media/images/avatars/small/27i97a.jpeg 300w\">"
  end
end

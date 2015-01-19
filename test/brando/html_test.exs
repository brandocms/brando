defmodule Brando.HTMLTest do
  use ExUnit.Case
  use Plug.Test
  import Brando.Util
  import Brando.HTML

  test "first_name/1" do
    assert first_name("John Josephs") == "John"
    assert first_name("John-Christian Josephs") == "John-Christian"
  end

  test "zero_pad/1" do
    assert zero_pad(1) == "001"
    assert zero_pad(10) == "010"
    assert zero_pad(100) == "100"
    assert zero_pad(1000) == "1000"
  end

  test "is_active?/2" do
    assert is_active?("/some/link", "/some/link") == "active"
    assert is_active?("/some/link", "/some/other/link") == ""
  end

  test "path/1" do
    conn = conn(:get, "/some/long/url")
    assert path(conn) == "/some/long/url"
    conn = conn(:get, "/url")
    assert path(conn) == "/url"
  end

  test "js_extra/2" do
    conn = conn(:get, "/")
    conn = conn |> add_js("test.js")
    assert conn.assigns[:js_extra] == "test.js"
    assert js_extra(conn) == {:safe, "<script type=\"text/javascript\" src=\"test.js\" charset=\"utf-8\"></script>"}
    conn = conn |> add_js(["test1.js", "test2.js"])
    assert conn.assigns[:js_extra] == ["test1.js", "test2.js"]
    assert js_extra(conn) ==
      [safe: "<script type=\"text/javascript\" src=\"test1.js\" charset=\"utf-8\"></script>",
       safe: "<script type=\"text/javascript\" src=\"test2.js\" charset=\"utf-8\"></script>"]
  end

  test "css_extra/2" do
    conn = conn(:get, "/")
    conn = conn |> add_css("test.css")
    assert conn.assigns[:css_extra] == "test.css"
    assert css_extra(conn) == {:safe, "<link rel=\"stylesheet\" href=\"test.css\">"}
    conn = conn |> add_css(["test1.css", "test2.css"])
    assert conn.assigns[:css_extra] == ["test1.css", "test2.css"]
    assert css_extra(conn) ==
      [safe: "<link rel=\"stylesheet\" href=\"test1.css\">",
       safe: "<link rel=\"stylesheet\" href=\"test2.css\">"]
  end
end
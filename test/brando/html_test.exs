defmodule Brando.HTMLTest do
  use ExUnit.Case, async: true
  use Plug.Test
  import Brando.Utils
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

  test "active_path/2" do
    conn = conn(:get, "/some/link")
    assert active_path(conn, "/some/link") == "active"
    assert active_path(conn, "/some/other/link") == ""
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

  test "format_date/1" do
    date = %Ecto.DateTime{year: 2015, month: 1, day: 1}
    assert format_date(date) == "1/1/2015"
  end

  test "media_url/1" do
    assert media_url("test") == "/media/test"
    assert media_url(nil) == "/media"
  end

  test "delete_form_button/2" do
    {:safe, ret} = delete_form_button(%{id: 1}, :admin_user_path)
    assert ret =~ "/admin/brukere/1"
    assert ret =~ "value=\"delete\""
  end

  test "check_or_x/1" do
    assert check_or_x(false) == {:safe, "<i class=\"fa fa-times text-danger\"></i>"}
    assert check_or_x(nil) == {:safe, "<i class=\"fa fa-times text-danger\"></i>"}
    assert check_or_x(true) == {:safe, "<i class=\"fa fa-check text-success\"></i>"}
  end
end
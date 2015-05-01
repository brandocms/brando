defmodule Brando.HTMLTest do
  use ExUnit.Case, async: true
  use Plug.Test
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
    assert zero_pad("1") == "001"
  end

  test "active_path/2" do
    conn = conn(:get, "/some/link")
    assert active_path(conn, "/some/link") == "active"
    assert active_path(conn, "/some/other/link") == ""
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
    {:safe, ret} = delete_form_button(%{__struct__: :user, id: 1}, :admin_user_path)
    assert ret =~ "/admin/brukere/1"
    assert ret =~ "value=\"delete\""
  end

  test "dropzone_form/3" do
    {:safe, form} = dropzone_form(:admin_image_series_path, 1, nil)
    assert form =~ "/admin/bilder/serier/1/last-opp"
    assert form =~ "dropzone"
  end

  test "check_or_x/1" do
    assert check_or_x(false) == "<i class=\"fa fa-times text-danger\"></i>"
    assert check_or_x(nil) == "<i class=\"fa fa-times text-danger\"></i>"
    assert check_or_x(true) == "<i class=\"fa fa-check text-success\"></i>"
  end
end
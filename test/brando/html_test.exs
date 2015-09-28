defmodule Brando.HTMLTest do
  use ExUnit.Case, async: true
  use Plug.Test
  use RouterHelper
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

  test "delete_form_button/2" do
    {:safe, ret} = delete_form_button("no", :admin_user_path,
                                      %{__struct__: :user, id: 1})
    assert ret =~ "/admin/users/1"
    assert ret =~ "value=\"delete\""
  end

  test "dropzone_form/3" do
    {:safe, form} = dropzone_form(:admin_image_series_path, 1)
    assert form =~ "/admin/images/series/1/upload"
    assert form =~ "dropzone"
  end

  test "check_or_x/1" do
    assert check_or_x(false) == "<i class=\"fa fa-times text-danger\"></i>"
    assert check_or_x(nil) == "<i class=\"fa fa-times text-danger\"></i>"
    assert check_or_x(true) == "<i class=\"fa fa-check text-success\"></i>"
  end

  test "auth_links" do
    conn = :get |> call("/admin/users") |> with_user

    assert auth_link(conn, "test", :admin, do: {:safe, "text"})
           == {:safe, "<a href=\"test\" class=\"btn btn-default\"> text</a>"}
    assert auth_link(:primary, conn, "test", :admin, do: {:safe, "text"})
           == {:safe, "<a href=\"test\" class=\"btn btn-primary\"> text</a>"}
    assert auth_link(:info, conn, "test", :admin, do: {:safe, "text"})
           == {:safe, "<a href=\"test\" class=\"btn btn-info\"> text</a>"}
    assert auth_link(:success, conn, "test", :admin, do: {:safe, "text"})
           == {:safe, "<a href=\"test\" class=\"btn btn-success\"> text</a>"}
    assert auth_link(:warning, conn, "test", :admin, do: {:safe, "text"})
           == {:safe, "<a href=\"test\" class=\"btn btn-warning\"> text</a>"}
    assert auth_link(:danger, conn, "test", :admin, do: {:safe, "text"})
           == {:safe, "<a href=\"test\" class=\"btn btn-danger\"> text</a>"}
  end
end

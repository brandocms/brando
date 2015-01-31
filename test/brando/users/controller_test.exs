Code.require_file("router_helper.exs", Path.join([__DIR__, "..", ".."]))

defmodule Brando.Users.ControllerTest do
  use ExUnit.Case
  use Brando.Integration.TestCase
  use Plug.Test
  use RouterHelper
  alias Brando.Users.Model.User

  @params %{"avatar" => "", "role" => ["2", "4"],
            "email" => "fanogigyni@gmail.com", "full_name" => "Nita Bond",
            "password" => "finimeze", "status" => "1",
            "submit" => "Submit", "username" => "zabuzasixu"}

  test "index redirects to /login when no :current_user" do
    conn = call_with_session(RouterHelper.TestRouter, :get, "/admin/brukere")
    assert conn.status == 302
    assert get_resp_header(conn, "Location") == ["/login"]
  end

  test "index with logged in user" do
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/brukere")
    assert conn.status == 200
    assert conn.path_info == ["admin", "brukere"]
    assert conn.private.phoenix_layout == {Brando.Admin.LayoutView, "admin.html"}
  end

  test "show" do
    assert {:ok, user} = User.create(@params)
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/brukere/#{user.id}")
    assert conn.status == 200
    assert conn.path_info == ["admin", "brukere", "#{user.id}"]
    assert conn.private.phoenix_layout == {Brando.Admin.LayoutView, "admin.html"}
    assert conn.resp_body =~ "Nita Bond"
  end

  test "profile" do
    assert {:ok, _user} = User.create(@params)
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/brukere/profil")
    assert conn.status == 200
    assert conn.path_info == ["admin", "brukere", "profil"]
    assert conn.private.phoenix_layout == {Brando.Admin.LayoutView, "admin.html"}
    assert conn.resp_body =~ "iggypop"
  end

  test "new" do
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/brukere/new")
    assert conn.status == 200
    assert conn.path_info == ["admin", "brukere", "new"]
    assert conn.private.phoenix_layout == {Brando.Admin.LayoutView, "admin.html"}
  end

  test "edit" do
    assert {:ok, user} = User.create(@params)
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/brukere/#{user.id}/edit")
    assert conn.status == 200
    assert conn.path_info == ["admin", "brukere", "#{user.id}", "edit"]
    assert conn.private.phoenix_layout == {Brando.Admin.LayoutView, "admin.html"}
    assert conn.resp_body =~ "value=\"Nita Bond\""
  end

  test "create (post)" do
    conn = call_with_user(RouterHelper.TestRouter, :post, "/admin/brukere/")
    assert conn.status == 200
    assert conn.path_info == ["admin", "brukere"]
    assert conn.private.phoenix_layout == {Brando.Admin.LayoutView, "admin.html"}
    assert conn.resp_body =~ "<form class=\"grid-form\" role=\"form\" action=\"/whatever\""
  end

  test "delete" do
    assert {:ok, user} = User.create(@params)
    conn = call_with_user(RouterHelper.TestRouter, :delete, "/admin/brukere/#{user.id}")
    assert conn.status == 302
    assert conn.path_info == ["admin", "brukere", "#{user.id}"]
    assert conn.private.phoenix_layout == {Brando.Admin.LayoutView, "admin.html"}
    assert get_resp_header(conn, "Location") == ["/admin/brukere"]
  end
end
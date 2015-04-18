Code.require_file("router_helper.exs", Path.join([__DIR__, "..", ".."]))

defmodule Brando.News.ControllerTest do
  use ExUnit.Case
  use Brando.Integration.TestCase
  use Plug.Test
  use RouterHelper
  alias Brando.Post
  alias Brando.User

  @user_params %{"avatar" => nil, "role" => ["2", "4"],
                 "email" => "fanogigyni@gmail.com", "full_name" => "Nita Bond",
                 "password" => "finimeze", "status" => "1",
                 "submit" => "Submit", "username" => "zabuzasixu"}

  @post_params %{"data" => "[{\"type\":\"text\",\"data\":{\"text\":\"zcxvxcv\"}}]",
                 "featured" => true, "header" => "Header",
                 "html" => "<h1>Header</h1><p>Asdf\nAsdf\nAsdf</p>\n",
                 "language" => "no", "lead" => "Asdf",
                 "meta_description" => nil, "meta_keywords" => nil,
                 "publish_at" => nil, "published" => false,
                 "slug" => "header", "status" => :published}

  @broken_post_params %{"data" => "", "featured" => true, "header" => "",
                        "html" => "<h1>Header</h1><p>Asdf\nAsdf\nAsdf</p>\n",
                        "language" => "no", "lead" => "Asdf",
                        "meta_description" => nil, "meta_keywords" => nil,
                        "publish_at" => "1", "published" => false,
                        "slug" => "header", "status" => :published}

  def create_user do
    {:ok, user} = User.create(@user_params)
    user
  end

  test "index" do
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/nyheter")
    assert conn.status == 200
    assert conn.path_info == ["admin", "nyheter"]
    assert conn.private.phoenix_layout == {Brando.Admin.LayoutView, "admin.html"}
  end

  test "show" do
    user = create_user
    assert {:ok, post} = Post.create(@post_params, user)
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/nyheter/#{post.id}")
    assert conn.status == 200
    assert conn.path_info == ["admin", "nyheter", "#{post.id}"]
    assert conn.private.phoenix_layout == {Brando.Admin.LayoutView, "admin.html"}
    assert conn.resp_body =~ "Header"
    assert conn.resp_body =~ "zabuzasixu"
  end

  test "new" do
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/nyheter/ny")
    assert conn.status == 200
    assert conn.path_info == ["admin", "nyheter", "ny"]
    assert conn.private.phoenix_layout == {Brando.Admin.LayoutView, "admin.html"}
  end

  test "edit" do
    user = create_user
    assert {:ok, post} = Post.create(@post_params, user)
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/nyheter/#{post.id}/endre")
    assert conn.status == 200
    assert conn.path_info == ["admin", "nyheter", "#{post.id}", "endre"]
    assert conn.private.phoenix_layout == {Brando.Admin.LayoutView, "admin.html"}
    assert conn.resp_body =~ "Endre post"
    assert conn.resp_body =~ "value=\"Header\""
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/nyheter/1234/endre")
    assert conn.status == 404

  end

  test "create (post) w/params" do
    user = create_user
    post_params = Map.put(@post_params, "creator_id", user.id)
    conn = call_with_custom_user(RouterHelper.TestRouter, :post, "/admin/nyheter/", %{"post" => post_params}, user: user)
    assert conn.status == 302
    assert get_resp_header(conn, "Location") == ["/admin/nyheter"]
    assert conn.path_info == ["admin", "nyheter"]
    assert conn.private.phoenix_layout == {Brando.Admin.LayoutView, "admin.html"}
    %{phoenix_flash: flash} = conn.private
    assert flash == %{"notice" => "Post opprettet."}
  end

  test "create (post) w/erroneus params" do
    conn = call_with_user(RouterHelper.TestRouter, :post, "/admin/nyheter/", %{"post" => @broken_post_params})
    assert conn.status == 200
    assert conn.path_info == ["admin", "nyheter"]
    assert conn.private.phoenix_layout == {Brando.Admin.LayoutView, "admin.html"}
    %{phoenix_flash: flash} = conn.private
    assert flash == %{"error" => "Feil i skjema"}
  end

  test "update (post) w/params" do
    user = create_user
    post_params = Map.put(@post_params, "creator_id", user.id)
    assert {:ok, post} = Post.create(post_params, user)
    conn = call_with_user(RouterHelper.TestRouter, :patch, "/admin/nyheter/#{post.id}", %{"post" => post_params})
    assert conn.status == 302
    assert get_resp_header(conn, "Location") == ["/admin/nyheter"]
    assert conn.path_info == ["admin", "nyheter", "#{post.id}"]
    assert conn.private.phoenix_layout == {Brando.Admin.LayoutView, "admin.html"}
    %{phoenix_flash: flash} = conn.private
    assert flash == %{"notice" => "Post oppdatert."}
  end

  test "delete_confirm" do
    user = create_user
    assert {:ok, post} = Post.create(@post_params, user)
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/nyheter/#{post.id}/slett")
    assert conn.status == 200
    assert conn.path_info == ["admin", "nyheter", "#{post.id}", "slett"]
    assert conn.resp_body =~ "Slett post: Header"
  end

  test "delete" do
    user = create_user
    assert {:ok, post} = Post.create(@post_params, user)
    conn = call_with_user(RouterHelper.TestRouter, :delete, "/admin/nyheter/#{post.id}")
    assert conn.status == 302
    assert conn.path_info == ["admin", "nyheter", "#{post.id}"]
    assert conn.private.phoenix_layout == {Brando.Admin.LayoutView, "admin.html"}
    assert get_resp_header(conn, "Location") == ["/admin/nyheter"]
  end
end
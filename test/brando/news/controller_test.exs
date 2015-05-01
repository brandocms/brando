#Code.require_file("router_helper.exs", Path.join([__DIR__, "..", ".."]))

defmodule Brando.News.ControllerTest do
  use ExUnit.Case
  use Brando.ConnCase
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
    assert response_content_type(conn, :html) =~ "charset=utf-8"
    assert html_response(conn, 200) =~ "Postoversikt"
  end

  test "show" do
    user = create_user
    assert {:ok, post} = Post.create(@post_params, user)
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/nyheter/#{post.id}")
    assert html_response(conn, 200) =~ "Header"
  end

  test "new" do
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/nyheter/ny")
    assert html_response(conn, 200) =~ "Ny post"
  end

  test "edit" do
    user = create_user
    assert {:ok, post} = Post.create(@post_params, user)
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/nyheter/#{post.id}/endre")
    assert html_response(conn, 200) =~ "Endre post"
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/nyheter/1234/endre")
    assert html_response(conn, 404)
  end

  test "create (post) w/params" do
    user = create_user
    post_params = Map.put(@post_params, "creator_id", user.id)
    conn = call_with_custom_user(RouterHelper.TestRouter, :post, "/admin/nyheter/", %{"post" => post_params}, user: user)
    assert redirected_to(conn, 302) =~ "/admin/nyheter"
    assert get_flash(conn, :notice) == "Post opprettet."
  end

  test "create (post) w/erroneus params" do
    conn = call_with_user(RouterHelper.TestRouter, :post, "/admin/nyheter/", %{"post" => @broken_post_params})
    assert html_response(conn, 200) =~ "Ny post"
    assert get_flash(conn, :error) == "Feil i skjema"
  end

  test "update (post) w/params" do
    user = create_user
    post_params = Map.put(@post_params, "creator_id", user.id)
    assert {:ok, post} = Post.create(post_params, user)
    conn = call_with_user(RouterHelper.TestRouter, :patch, "/admin/nyheter/#{post.id}", %{"post" => post_params})
    assert redirected_to(conn, 302) =~ "/admin/nyheter"
    assert get_flash(conn, :notice) == "Post oppdatert."
  end

  test "delete_confirm" do
    user = create_user
    assert {:ok, post} = Post.create(@post_params, user)
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/nyheter/#{post.id}/slett")
    assert html_response(conn, 200) =~ "Slett post: Header"
  end

  test "delete" do
    user = create_user
    assert {:ok, post} = Post.create(@post_params, user)
    conn = call_with_user(RouterHelper.TestRouter, :delete, "/admin/nyheter/#{post.id}")
    assert redirected_to(conn, 302) =~ "/admin/nyheter"
  end
end
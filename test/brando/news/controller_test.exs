#Code.require_file("router_helper.exs", Path.join([__DIR__, "..", ".."]))

defmodule Brando.News.ControllerTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  use Plug.Test
  use RouterHelper
  alias Brando.Post
  alias Brando.User

  @user_params %{"avatar" => nil, "role" => ["2", "4"], "language" => "nb",
                 "email" => "fanogigyni@gmail.com", "full_name" => "Nita Bond",
                 "password" => "finimeze", "status" => "1",
                 "submit" => "Submit", "username" => "zabuzasixu"}

  @post_params %{"data" => "[{\"type\":\"text\",\"data\":" <>
                 "{\"text\":\"zcxvxcv\",\"type\":\"paragraph\"}}]",
                 "featured" => true, "header" => "Header",
                 "html" => "<h1>Header</h1><p>Asdf\nAsdf\nAsdf</p>\n",
                 "language" => "nb", "lead" => "Asdf",
                 "meta_description" => nil, "meta_keywords" => nil,
                 "publish_at" => nil, "published" => false,
                 "slug" => "header", "status" => :published}

  @broken_post_params %{"data" => "", "featured" => true, "header" => "",
                        "html" => "<h1>Header</h1><p>Asdf\nAsdf\nAsdf</p>\n",
                        "language" => "nb", "lead" => "Asdf",
                        "meta_description" => nil, "meta_keywords" => nil,
                        "publish_at" => "1", "published" => false,
                        "slug" => "header", "status" => :published}

  def create_user do
    {:ok, user} = User.create(@user_params)
    user
  end

  test "index" do
    conn =
      :get
      |> call("/admin/news")
      |> with_user
      |> send_request

    assert response_content_type(conn, :html) =~ "charset=utf-8"
    assert html_response(conn, 200) =~ "Index - posts"
  end

  test "show" do
    user = create_user

    assert {:ok, post} = Post.create(@post_params, user)

    conn =
      :get
      |> call("/admin/news/#{post.id}")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Header"
  end

  test "new" do
    conn =
      :get
      |> call("/admin/news/new")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "New post"
  end

  test "edit" do
    user = create_user

    assert {:ok, post} = Post.create(@post_params, user)

    conn =
      :get
      |> call("/admin/news/#{post.id}/edit")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Edit post"

    assert_raise Plug.Conn.WrapperError, fn ->
      :get
      |> call("/admin/news/1234/edit")
      |> with_user
      |> send_request
    end
  end

  test "create (post) w/params" do
    user = create_user
    conn =
      :post
      |> call("/admin/news/", %{"post" => Map.put(@post_params, "creator_id",
                                                  user.id)})
      |> with_user(user)
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/news"
  end

  test "create (post) w/erroneus params" do
    conn =
      :post
      |> call("/admin/news/", %{"post" => @broken_post_params})
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "New post"
    assert get_flash(conn, :error) == "Errors in form"
  end

  test "update (post) w/params" do
    user = create_user
    post_params = Map.put(@post_params, "creator_id", user.id)

    assert {:ok, post} = Post.create(post_params, user)

    post_params =
      Map.put(post_params, "data", "[{\"type\":\"text\",\"data\":" <>
              "{\"text\":\"zcxvxcv\",\"type\":\"paragraph\"}}]")

    conn =
      :patch
      |> call("/admin/news/#{post.id}", %{"post" => post_params})
      |> with_user(user)
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/news"
  end

  test "delete_confirm" do
    user = create_user

    assert {:ok, post} = Post.create(@post_params, user)

    conn =
      :get
      |> call("/admin/news/#{post.id}/delete")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Delete post: Header"
  end

  test "delete" do
    user = create_user

    assert {:ok, post} = Post.create(@post_params, user)

    conn =
      :delete
      |> call("/admin/news/#{post.id}")
      |> with_user
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/news"
  end

  test "uses villain" do
    funcs = Brando.Admin.PostController.__info__(:functions)
    funcs =
      funcs
      |> Keyword.keys

    assert :browse_images in funcs
    assert :upload_image in funcs
    assert :image_info in funcs
  end
end

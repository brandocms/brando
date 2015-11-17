defmodule Brando.Pages.ControllerTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  use Plug.Test
  use RouterHelper
  alias Brando.Page
  alias Brando.User

  @user_params %{"avatar" => nil, "role" => ["2", "4"], "language" => "nb",
                 "email" => "fanogigyni@gmail.com", "full_name" => "Nita Bond",
                 "password" => "finimeze", "status" => "1",
                 "submit" => "Submit", "username" => "zabuzasixu"}

  @page_params %{"data" => "[{\"type\":\"text\",\"data\":" <>
                           "{\"text\":\"zcxvxcv\",\"type\":\"paragraph\"}}]",
                 "title" => "Header",
                 "key" => "testpage",
                 "html" => "<h1>Header</h1><p>Asdf\nAsdf\nAsdf</p>\n",
                 "language" => "nb",
                 "meta_description" => nil, "meta_keywords" => nil,
                 "slug" => "header", "status" => :published,
                 "css_classes" => "extra-class"}

  @broken_page_params %{"data" => "", "featured" => true, "title" => "",
                        "key" => "testpage",
                        "html" => "<h1>Header</h1><p>Asdf\nAsdf\nAsdf</p>\n",
                        "language" => "nb",
                        "meta_description" => nil, "meta_keywords" => nil,
                        "slug" => "header", "status" => :published}

  def create_user do
    {:ok, user} = User.create(@user_params)
    user
  end

  test "index" do
    conn =
      :get
      |> call("/admin/pages")
      |> with_user
      |> send_request

    assert response_content_type(conn, :html) =~ "charset=utf-8"
    assert html_response(conn, 200) =~ "Index - pages"
  end

  test "show" do
    user = create_user

    assert {:ok, page} = Page.create(@page_params, user)

    conn =
      :get
      |> call("/admin/pages/#{page.id}")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Header"
  end

  test "new" do
    conn =
      :get
      |> call("/admin/pages/new")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "New page"
  end

  test "edit" do
    user = create_user

    assert {:ok, page} = Page.create(@page_params, user)

    conn =
      :get
      |> call("/admin/pages/#{page.id}/edit")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Edit page"

    assert_raise Plug.Conn.WrapperError, fn ->
      :get
      |> call("/admin/pages/1234/edit")
      |> with_user
      |> send_request
    end
  end

  test "duplicate" do
    user = create_user

    assert {:ok, page} = Page.create(@page_params, user)

    conn =
      :get
      |> call("/admin/pages/#{page.id}/duplicate")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "zcxvxcv"
    assert get_flash(conn, :notice) == "Page duplicated"
  end

  test "encode_data" do
    assert Brando.Page.encode_data(%{data: "test"})
           == %{data: "test"}
    assert Brando.Page.encode_data(%{data: ["test", "test2"]})
           == %{data: ~s(["test","test2"])}
  end

  test "create (page) w/params" do
    user = create_user
    conn =
      :post
      |> call("/admin/pages/",
              %{"page" => Map.put(@page_params, "creator_id", user.id)})
      |> with_user(user)
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/pages"
  end

  test "create (page) w/erroneus params" do
    conn =
      :post
      |> call("/admin/pages/", %{"page" => @broken_page_params})
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "New page"
    assert get_flash(conn, :error) == "Errors in form"
  end

  test "update (page) w/params" do
    user = create_user
    page_params = Map.put(@page_params, "creator_id", user.id)

    assert {:ok, page} = Page.create(page_params, user)

    page_params = Map.put(page_params, "data",
                          "[{\"type\":\"text\",\"data\":" <>
                          "{\"text\":\"zcxvxcv\",\"type\":\"paragraph\"}}]")

    conn =
      :patch
      |> call("/admin/pages/#{page.id}", %{"page" => page_params})
      |> with_user(user)
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/pages"
  end

  test "delete_confirm" do
    user = create_user

    assert {:ok, page} = Page.create(@page_params, user)

    conn =
      :get
      |> call("/admin/pages/#{page.id}/delete")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Delete page: Header"
  end

  test "delete" do
    user = create_user

    assert {:ok, page} = Page.create(@page_params, user)

    conn =
      :delete
      |> call("/admin/pages/#{page.id}")
      |> with_user
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/pages"
  end

  test "uses villain" do
    funcs = Brando.Admin.PageController.__info__(:functions)
    funcs = Keyword.keys(funcs)

    assert :browse_images in funcs
    assert :upload_image in funcs
    assert :image_info in funcs
  end
end

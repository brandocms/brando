defmodule Brando.Pages.ControllerTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  use Plug.Test
  use RouterHelper
  alias Brando.Page
  alias Brando.User

  @user_params %{"avatar" => nil, "role" => ["2", "4"], "language" => "no",
                 "email" => "fanogigyni@gmail.com", "full_name" => "Nita Bond",
                 "password" => "finimeze", "status" => "1",
                 "submit" => "Submit", "username" => "zabuzasixu"}

  @page_params %{"data" => "[{\"type\":\"text\",\"data\":{\"text\":\"zcxvxcv\",\"type\":\"paragraph\"}}]",
                 "title" => "Header",
                 "key" => "testpage",
                 "html" => "<h1>Header</h1><p>Asdf\nAsdf\nAsdf</p>\n",
                 "language" => "no",
                 "meta_description" => nil, "meta_keywords" => nil,
                 "slug" => "header", "status" => :published}

  @broken_page_params %{"data" => "", "featured" => true, "title" => "",
                        "key" => "testpage",
                        "html" => "<h1>Header</h1><p>Asdf\nAsdf\nAsdf</p>\n",
                        "language" => "no",
                        "meta_description" => nil, "meta_keywords" => nil,
                        "slug" => "header", "status" => :published}

  def create_user do
    {:ok, user} = User.create(@user_params)
    user
  end

  test "index" do
    conn =
      call(:get, "/admin/sider")
      |> with_user
      |> send_request

    assert response_content_type(conn, :html) =~ "charset=utf-8"
    assert html_response(conn, 200) =~ "Sideoversikt"
  end

  test "show" do
    user = create_user

    assert {:ok, page} = Page.create(@page_params, user)

    conn =
      call(:get, "/admin/sider/#{page.id}")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Header"
  end

  test "new" do
    conn =
      call(:get, "/admin/sider/ny")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Ny side"
  end

  test "edit" do
    user = create_user

    assert {:ok, page} = Page.create(@page_params, user)

    conn =
      call(:get, "/admin/sider/#{page.id}/endre")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Endre side"

    assert_raise Plug.Conn.WrapperError, fn ->
      call(:get, "/admin/sider/1234/endre")
      |> with_user
      |> send_request
    end
  end

  test "create (page) w/params" do
    user = create_user
    conn =
      call(:post, "/admin/sider/", %{"page" => Map.put(@page_params, "creator_id", user.id)})
      |> with_user(user)
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/sider"
    assert get_flash(conn, :notice) == "Side opprettet"
  end

  test "create (page) w/erroneus params" do
    conn =
      call(:post, "/admin/sider/", %{"page" => @broken_page_params})
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Ny side"
    assert get_flash(conn, :error) == "Feil i skjema"
  end

  test "update (page) w/params" do
    user = create_user
    page_params = Map.put(@page_params, "creator_id", user.id)

    assert {:ok, page} = Page.create(page_params, user)

    page_params = Map.put(page_params, "data", "[{\"type\":\"text\",\"data\":{\"text\":\"zcxvxcv\",\"type\":\"paragraph\"}}]")

    conn =
      call(:patch, "/admin/sider/#{page.id}", %{"page" => page_params})
      |> with_user(user)
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/sider"
    assert get_flash(conn, :notice) == "Side oppdatert"
  end

  test "delete_confirm" do
    user = create_user

    assert {:ok, page} = Page.create(@page_params, user)

    conn =
      call(:get, "/admin/sider/#{page.id}/slett")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Slett side: Header"
  end

  test "delete" do
    user = create_user

    assert {:ok, page} = Page.create(@page_params, user)

    conn =
      call(:delete, "/admin/sider/#{page.id}")
      |> with_user
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/sider"
  end

  test "uses villain" do
    funcs = Brando.Admin.PageController.__info__(:functions) |> Keyword.keys

    assert :browse_images in funcs
    assert :upload_image in funcs
    assert :image_info in funcs
  end
end
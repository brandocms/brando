defmodule Brando.PageFragments.ControllerTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  use Plug.Test
  use RouterHelper
  alias Brando.PageFragment
  alias Brando.User

  @user_params %{"avatar" => nil, "role" => ["2", "4"],
                 "email" => "fanogigyni@gmail.com", "full_name" => "Nita Bond",
                 "password" => "finimeze", "status" => "1",
                 "submit" => "Submit", "username" => "zabuzasixu"}

  @page_params %{"data" => "[{\"type\":\"text\",\"data\":{\"text\":\"zcxvxcv\"}}]",
                 "key" => "testpage",
                 "html" => "<h1>Header</h1><p>Asdf\nAsdf\nAsdf</p>\n",
                 "language" => "no"}

  @broken_page_params %{"data" => "", "featured" => true, "title" => "",
                        "key" => "testpage",
                        "html" => "<h1>Header</h1><p>Asdf\nAsdf\nAsdf</p>\n",
                        "language" => "no"}

  def create_user do
    {:ok, user} = User.create(@user_params)
    user
  end

  test "index" do
    conn =
      call(:get, "/admin/sider/fragmenter")
      |> with_user
      |> send_request

    assert response_content_type(conn, :html) =~ "charset=utf-8"
    assert html_response(conn, 200) =~ "Sidefragmentoversikt"
  end

  test "show" do
    user = create_user

    assert {:ok, page} = PageFragment.create(@page_params, user)

    conn =
      call(:get, "/admin/sider/fragmenter/#{page.id}")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "testpage"
  end

  test "new" do
    conn =
      call(:get, "/admin/sider/fragmenter/ny")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Nytt sidefragment"
  end

  test "edit" do
    user = create_user

    assert {:ok, page} = PageFragment.create(@page_params, user)

    conn =
      call(:get, "/admin/sider/fragmenter/#{page.id}/endre")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Endre sidefragment"

    assert_raise Plug.Conn.WrapperError, fn ->
      call(:get, "/admin/sider/fragmenter/1234/endre")
      |> with_user
      |> send_request
    end
  end

  test "create (page) w/params" do
    user = create_user
    conn =
      call(:post, "/admin/sider/fragmenter/", %{"page_fragment" => Map.put(@page_params, "creator_id", user.id)})
      |> with_user(user)
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/sider/fragmenter"
    assert get_flash(conn, :notice) == "Sidefragment opprettet."
  end

  test "create (page) w/erroneus params" do
    conn =
      call(:post, "/admin/sider/fragmenter/", %{"page_fragment" => @broken_page_params})
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Nytt sidefragment"
    assert get_flash(conn, :error) == "Feil i skjema"
  end

  test "update (page) w/params" do
    user = create_user
    page_params = Map.put(@page_params, "creator_id", user.id)

    assert {:ok, page} = PageFragment.create(page_params, user)

    page_params = Map.put(page_params, "data", "[{\"type\":\"text\",\"data\":{\"text\":\"asdf\"}}]")

    conn =
      call(:patch, "/admin/sider/fragmenter/#{page.id}", %{"page_fragment" => page_params})
      |> with_user(user)
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/sider/fragmenter"
    assert get_flash(conn, :notice) == "Sidefragment oppdatert."
  end

  test "delete_confirm" do
    user = create_user

    assert {:ok, page} = PageFragment.create(@page_params, user)

    conn =
      call(:get, "/admin/sider/fragmenter/#{page.id}/slett")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Slett sidefragment: testpage"
  end

  test "delete" do
    user = create_user

    assert {:ok, page} = PageFragment.create(@page_params, user)

    conn =
      call(:delete, "/admin/sider/fragmenter/#{page.id}")
      |> with_user
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/sider/fragmenter"
  end

  test "uses villain" do
    funcs = Brando.Admin.PageFragmentController.__info__(:functions) |> Keyword.keys

    assert :browse_images in funcs
    assert :upload_image in funcs
    assert :image_info in funcs
  end
end
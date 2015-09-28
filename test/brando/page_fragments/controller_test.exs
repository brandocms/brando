defmodule Brando.PageFragments.ControllerTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  use Plug.Test
  use RouterHelper
  alias Brando.PageFragment
  alias Brando.User

  @user_params %{"avatar" => nil, "role" => ["2", "4"], "language" => "no",
                 "email" => "fanogigyni@gmail.com", "full_name" => "Nita Bond",
                 "password" => "finimeze", "status" => "1",
                 "submit" => "Submit", "username" => "zabuzasixu"}

  @page_params %{"data" => "[{\"type\":\"text\",\"data\":" <>
                 "{\"text\":\"zcxvxcv\",\"type\":\"paragraph\"}}]",
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
      :get
      |> call("/admin/pages/fragments")
      |> with_user
      |> send_request

    assert response_content_type(conn, :html) =~ "charset=utf-8"
    assert html_response(conn, 200) =~ "Sidefragmentoversikt"
  end

  test "show" do
    user = create_user

    assert {:ok, page} = PageFragment.create(@page_params, user)

    conn =
      :get
      |> call("/admin/pages/fragments/#{page.id}")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "testpage"
  end

  test "new" do
    conn =
      :get
      |> call("/admin/pages/fragments/new")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Opprett sidefragment"
  end

  test "edit" do
    user = create_user

    assert {:ok, page} = PageFragment.create(@page_params, user)

    conn =
      :get
      |> call("/admin/pages/fragments/#{page.id}/edit")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Endre sidefragment"

    assert_raise Plug.Conn.WrapperError, fn ->
      :get
      |> call("/admin/pages/fragments/1234/edit")
      |> with_user
      |> send_request
    end
  end

  test "create (page) w/params" do
    user = create_user
    conn =
      :post
      |> call("/admin/pages/fragments/",
              %{"page_fragment" => Map.put(@page_params,
                                           "creator_id", user.id)})
      |> with_user(user)
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/pages/fragments"
    assert get_flash(conn, :notice) == "Sidefragment opprettet"
  end

  test "create (page) w/erroneus params" do
    conn =
      :post
      |> call("/admin/pages/fragments/",
              %{"page_fragment" => @broken_page_params})
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Opprett sidefragment"
    assert get_flash(conn, :error) == "Feil i skjema"
  end

  test "update (page) w/params" do
    user = create_user
    page_params = Map.put(@page_params, "creator_id", user.id)

    assert {:ok, page} = PageFragment.create(page_params, user)

    page_params =
      Map.put(page_params, "data", "[{\"type\":\"text\",\"data\":" <>
              "{\"text\":\"zcxvxcv\",\"type\":\"paragraph\"}}]")

    conn =
      :patch
      |> call("/admin/pages/fragments/#{page.id}",
              %{"page_fragment" => page_params})
      |> with_user(user)
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/pages/fragments"
    assert get_flash(conn, :notice) == "Sidefragment oppdatert"
  end

  test "delete_confirm" do
    user = create_user

    assert {:ok, page} = PageFragment.create(@page_params, user)

    conn =
      :get
      |> call("/admin/pages/fragments/#{page.id}/delete")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Slett sidefragment: testpage"
  end

  test "delete" do
    user = create_user

    assert {:ok, page} = PageFragment.create(@page_params, user)

    conn =
      :delete
      |> call("/admin/pages/fragments/#{page.id}")
      |> with_user
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/pages/fragments"
  end

  test "uses villain" do
    funcs =
      :functions
      |> Brando.Admin.PageFragmentController.__info__
      |> Keyword.keys

    assert :browse_images in funcs
    assert :upload_image in funcs
    assert :image_info in funcs
    assert :imageseries in funcs
  end
end

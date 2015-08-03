#Code.require_file("router_helper.exs", Path.join([__DIR__, "..", ".."]))

defmodule Brando.ImageCategory.ControllerTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  use Plug.Test
  use RouterHelper
  alias Brando.ImageCategory
  alias Brando.User
  alias Brando.Type.ImageConfig

  @user_params %{"avatar" => nil, "role" => ["2", "4"], "language" => "no",
                 "email" => "fanogigyni@gmail.com", "full_name" => "Nita Bond",
                 "password" => "finimeze", "status" => "1",
                 "submit" => "Submit", "username" => "zabuzasixu"}
  @params %{"cfg" => %ImageConfig{}, "name" => "Test Category", "slug" => "test-category"}
  @broken_params %{"cfg" => %ImageConfig{}}

  def create_user do
    {:ok, user} = User.create(@user_params)
    user
  end

  test "new" do
    conn =
      call(:get, "/admin/images/categories/new")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Ny bildekategori"
  end

  test "edit" do
    user = create_user
    assert {:ok, category} = ImageCategory.create(@params, user)
    conn =
      call(:get, "/admin/images/categories/#{category.id}/edit")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Endre bildekategori"

    assert_raise Plug.Conn.WrapperError, fn ->
      call(:get, "/admin/images/categories/1234/edit")
      |> with_user
      |> send_request
    end
  end

  test "create (post) w/params" do
    user = create_user
    conn =
      call(:post, "/admin/images/categories/", %{"imagecategory" => Map.put(@params, "creator_id", user.id)})
      |> with_user
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/images"
    assert get_flash(conn, :notice) == "Bildekategori opprettet"
  end

  test "create (post) w/erroneus params" do
    conn =
      call(:post, "/admin/images/categories/", %{"imagecategory" => @broken_params})
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Ny bildekategori"
    assert get_flash(conn, :error) == "Feil i skjema"
  end

  test "update (post) w/params" do
    user = create_user
    params = Map.put(@params, "creator_id", user.id)

    assert {:ok, category} = ImageCategory.create(params, user)

    conn =
      call(:patch, "/admin/images/categories/#{category.id}", %{"imagecategory" => params})
      |> with_user
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/images"
    assert get_flash(conn, :notice) == "Bildekategori oppdatert"
  end

  test "config (get)" do
    user = create_user

    assert {:ok, category} = ImageCategory.create(@params, user)

    conn =
      call(:get, "/admin/images/categories/#{category.id}/configure")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Konfigurér bildekategori"
    assert html_response(conn, 200) =~ "imagecategoryconfig[cfg]"

    assert_raise Plug.Conn.WrapperError, fn ->
      call(:get, "/admin/images/categories/1234/configure")
      |> with_user
      |> send_request
    end
  end

  test "config (post) w/params" do
    user = create_user
    params = Map.put(@params, "creator_id", user.id)

    assert {:ok, category} = ImageCategory.create(params, user)

    conn =
      call(:patch, "/admin/images/categories/#{category.id}/configure", %{"imagecategoryconfig" => params})
      |> with_user
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/images"
    assert get_flash(conn, :notice) == "Bildekategori konfigurert"
  end

  test "delete_confirm" do
    user = create_user

    assert {:ok, category} = ImageCategory.create(@params, user)

    conn =
      call(:get, "/admin/images/categories/#{category.id}/delete")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Slett bildekategori: Test Category"
  end

  test "delete" do
    user = create_user
    assert {:ok, category} = ImageCategory.create(@params, user)
    conn =
      call(:delete, "/admin/images/categories/#{category.id}")
      |> with_user
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/images"
    assert get_flash(conn, :notice) == "Bildekategori slettet"
  end
end
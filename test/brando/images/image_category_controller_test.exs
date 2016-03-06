defmodule Brando.ImageCategory.ControllerTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  use Plug.Test
  use RouterHelper
  alias Brando.ImageCategory
  alias Brando.Type.ImageConfig

  @user_params %{"avatar" => nil, "role" => ["2", "4"], "language" => "nb",
                 "email" => "fanogigyni@gmail.com", "full_name" => "Nita Bond",
                 "password" => "finimeze", "status" => "1",
                 "submit" => "Submit", "username" => "zabuzasixu"}
  @params %{"cfg" => %ImageConfig{}, "name" => "Test Category",
            "slug" => "test-category"}
  @broken_params %{"cfg" => %ImageConfig{}}

  def create_user do
    {:ok, user} = create_user(@user_params)
    user
  end

  test "new" do
    conn =
      :get
      |> call("/admin/images/categories/new")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "New image category"
  end

  test "edit" do
    user = create_user
    assert {:ok, category} = ImageCategory.create(@params, user)
    conn =
      :get
      |> call("/admin/images/categories/#{category.id}/edit")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Edit image category"

    assert_raise Plug.Conn.WrapperError, fn ->
      :get
      |> call("/admin/images/categories/1234/edit")
      |> with_user
      |> send_request
    end
  end

  test "create (post) w/params" do
    user = create_user
    conn =
      :post
      |> call("/admin/images/categories/",
              %{"imagecategory" => Map.put(@params, "creator_id", user.id)})
      |> with_user
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/images"
    assert get_flash(conn, :notice) == "Image category created"
  end

  test "create (post) w/erroneus params" do
    conn =
      :post
      |> call("/admin/images/categories/",
              %{"imagecategory" => @broken_params})
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "New image category"
    assert get_flash(conn, :error) == "Errors in form"
  end

  test "update (post) w/params" do
    user = create_user
    params = Map.put(@params, "creator_id", user.id)

    assert {:ok, category} = ImageCategory.create(params, user)

    conn =
      :patch
      |> call("/admin/images/categories/#{category.id}",
              %{"imagecategory" => params})
      |> with_user
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/images"
    assert get_flash(conn, :notice) == "Image category updated"
  end

  test "config (get)" do
    user = create_user

    assert {:ok, category} = ImageCategory.create(@params, user)

    conn =
      :get
      |> call("/admin/images/categories/#{category.id}/configure")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Configure image category"
    assert html_response(conn, 200) =~ "imagecategoryconfig[cfg]"

    assert_raise Plug.Conn.WrapperError, fn ->
      :get
      |> call("/admin/images/categories/1234/configure")
      |> with_user
      |> send_request
    end
  end

  test "config (post) w/params" do
    user = create_user
    params = Map.put(@params, "creator_id", user.id)

    assert {:ok, category} = ImageCategory.create(params, user)

    conn =
      :patch
      |> call("/admin/images/categories/#{category.id}/configure",
              %{"imagecategoryconfig" => params})
      |> with_user
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/images"
    assert get_flash(conn, :notice) == "Image category configured"
  end

  test "delete_confirm" do
    user = create_user

    assert {:ok, category} = ImageCategory.create(@params, user)

    conn =
      :get
      |> call("/admin/images/categories/#{category.id}/delete")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Delete image category: Test Category"
  end

  test "delete" do
    user = create_user
    assert {:ok, category} = ImageCategory.create(@params, user)
    conn =
      :delete
      |> call("/admin/images/categories/#{category.id}")
      |> with_user
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/images"
    assert get_flash(conn, :notice) == "Image category deleted"
  end
end

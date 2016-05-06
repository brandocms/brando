defmodule Brando.ImageCategory.ControllerTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  use Plug.Test
  use RouterHelper

  alias Brando.Type.ImageConfig
  alias Brando.Factory

  setup do
    user = Factory.create(:user)
    {:ok, %{user: user}}
  end

  test "new" do
    conn =
      :get
      |> call("/admin/images/categories/new")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "New image category"
  end

  test "edit", %{user: user} do
    category = Factory.create(:image_category, creator: user)

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

  test "create (post) w/params", %{user: user} do
    image_category_params = Factory.build(:image_category_params, %{"creator_id" => user.id})

    conn =
      :post
      |> call("/admin/images/categories/", %{"imagecategory" => image_category_params})
      |> with_user
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/images"
    assert get_flash(conn, :notice) == "Image category created"
  end

  test "create (post) w/erroneus params" do
    conn =
      :post
      |> call("/admin/images/categories/", %{"imagecategory" => %{"cfg" => %ImageConfig{}}})
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "New image category"
    assert get_flash(conn, :error) == "Errors in form"
  end

  test "update (post) w/params", %{user: user} do
    params = Factory.build(:image_category_params, %{"creator_id" => user.id})
    category = Factory.create(:image_category, creator: user)

    conn =
      :patch
      |> call("/admin/images/categories/#{category.id}", %{"imagecategory" => params})
      |> with_user
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/images"
    assert get_flash(conn, :notice) == "Image category updated"
  end

  test "config (get)", %{user: user} do
    category = Factory.create(:image_category, creator: user)

    conn =
      :get
      |> call("/admin/images/categories/#{category.id}/configure")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Configure image category"
    assert html_response(conn, 200) =~ "config"
    assert html_response(conn, 200) =~ "sizes"

    assert_raise Plug.Conn.WrapperError, fn ->
      :get
      |> call("/admin/images/categories/1234/configure")
      |> with_user
      |> send_request
    end
  end

  test "delete_confirm", %{user: user} do
    category = Factory.create(:image_category, creator: user)

    conn =
      :get
      |> call("/admin/images/categories/#{category.id}/delete")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Delete image category: Test Category"
  end

  test "delete", %{user: user} do
    category = Factory.create(:image_category, creator: user)
    conn =
      :delete
      |> call("/admin/images/categories/#{category.id}")
      |> with_user
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/images"
    assert get_flash(conn, :notice) == "Image category deleted"
  end
end

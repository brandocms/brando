defmodule Brando.ImageSeries.ControllerTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  use Plug.Test
  use RouterHelper

  alias Brando.Image
  alias Brando.ImageSeries
  alias Brando.Factory

  setup do
    user = Factory.insert(:user)
    category = Factory.insert(:image_category, creator: user)
    {:ok, %{user: user, category: category}}
  end

  test "new", %{category: category} do
    conn =
      :get
      |> call("/admin/images/series/new/#{category.id}")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "New image series"
  end

  test "edit", %{user: user, category: category} do
    series = Factory.insert(:image_series, creator: user, image_category: category)

    conn =
      :get
      |> call("/admin/images/series/#{series.id}/edit")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Edit image series"

    assert_raise Plug.Conn.WrapperError, fn ->
      :get
      |> call("/admin/images/series/1234/edit")
      |> with_user
      |> send_request
    end
  end

  test "create (post) w/params", %{user: user, category: category} do
    series_params = Factory.params_for(:image_series, %{creator_id: user.id,
                                                        image_category_id: category.id})

    conn =
      :post
      |> call("/admin/images/series/", %{"imageseries" => series_params})
      |> with_user(user)
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/images"
    assert get_flash(conn, :notice) == "Image series created"
  end

  test "update (post) w/params", %{user: user, category: category} do
    series = Factory.insert(:image_series, creator: user, image_category: category)
    series_params = Factory.params_for(:image_series, %{creator_id: user.id,
                                                        image_category_id: category.id})
    conn =
      :patch
      |> call("/admin/images/series/#{series.id}", %{"imageseries" => series_params})
      |> with_user
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/images"
    assert get_flash(conn, :notice) == "Image series updated"
  end

  test "delete_confirm", %{user: user, category: category} do
    series = Factory.insert(:image_series, creator: user, image_category: category)

    conn =
      :get
      |> call("/admin/images/series/#{series.id}/delete")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Delete image series: Series name"
  end

  test "delete", %{user: user, category: category} do
    series = Factory.insert(:image_series, creator: user, image_category: category)

    conn =
      :delete
      |> call("/admin/images/series/#{series.id}")
      |> with_user
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/images"
    assert get_flash(conn, :notice) == "Image series deleted"
  end

  test "upload", %{user: user, category: category} do
    series = Factory.insert(:image_series, creator: user, image_category: category)

    conn =
      :get
      |> call("/admin/images/series/#{series.id}/upload")
      |> with_user
      |> send_request

    assert html_response(conn, 200)
           =~ "<span class=\"text-normal\">Upload to this image series</span> &raquo; <strong>Series name</strong>"
  end

  test "upload_post", %{user: user, category: category} do
    File.rm_rf!(Brando.config(:media_path))
    File.mkdir_p!(Brando.config(:media_path))

    series = Factory.insert(:image_series, creator: user, image_category: category)
    up_params = Factory.build(:plug_upload)

    conn =
      :post
      |> call("/admin/images/series/#{series.id}/upload", %{"id" => series.id, "image" => up_params})
      |> with_user(user)
      |> as_json
      |> send_request

    assert json_response(conn, 200) == %{"status" => "200"}
  end

  test "sort", %{user: user, category: category} do
    File.rm_rf!(Brando.config(:media_path))
    File.mkdir_p!(Brando.config(:media_path))

    series      = Factory.insert(:image_series, creator: user, image_category: category)
    up_params   = Factory.build(:plug_upload)
    up_params_2 = Factory.build(:plug_upload_2)

    conn =
      :post
      |> call("/admin/images/series/#{series.id}/upload",
              %{"id" => series.id, "image" => up_params})
      |> with_user(user)
      |> as_json
      |> send_request

    assert conn.status == 200

    conn =
      :post
      |> call("/admin/images/series/#{series.id}/upload",
              %{"id" => series.id, "image" => up_params_2})
      |> with_user(user)
      |> as_json
      |> send_request

    assert conn.status == 200

    conn =
      :get
      |> call("/admin/images/series/#{series.id}/sort")
      |> with_user
      |> send_request

    assert conn.status == 200
    assert html_response(conn, 200)
           =~ "<img src=\"/media/portfolio/test-category/test-series/thumb/sample-optimized.png\" />"

    q = from(i in Image, order_by: i.id)

    series = Brando.repo.all(
      from is in ImageSeries,
        where: is.id == ^series.id,
        preload: [images: ^q]
    ) |> List.first

    [img1, img2] = series.images

    conn =
      :post
      |> call("/admin/images/series/#{series.id}/sort",
              %{"order" => [to_string(img2.id), to_string(img1.id)]})
      |> with_user(user)
      |> as_json
      |> send_request

    assert conn.status == 200
    assert conn.path_info == ["admin", "images", "series", "#{series.id}", "sort"]
    assert json_response(conn, 200) == %{"status" => "200"}

    series = Brando.repo.all(
      from is in ImageSeries,
        where: is.id == ^series.id,
        preload: [images: ^q]
    ) |> List.first

    [img1, img2] = series.images

    case img1.image.path do
      "portfolio/test-category/test-series/sample.png"  -> assert img1.sequence > img2.sequence
      "portfolio/test-category/test-series/sample2.png" -> assert img1.sequence < img2.sequence
    end
  end

  test "configure get", %{user: user, category: category} do
    series = Factory.insert(:image_series, creator: user, image_category: category)

    conn =
      :get
      |> call("/admin/images/series/#{series.id}/configure")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Configure image series"
  end
end

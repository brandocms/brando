defmodule Brando.ImageSeries.ControllerTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  use Plug.Test
  use RouterHelper
  alias Brando.ImageSeries
  alias Brando.ImageCategory
  alias Brando.Type.ImageConfig

  @path1 "#{Path.expand("../../", __DIR__)}/fixtures/sample.png"
  @path2 "#{Path.expand("../../", __DIR__)}/fixtures/sample2.png"
  @cfg Map.from_struct(%ImageConfig{})
  @cfg_changed Map.put(@cfg, :random_filename, true)
  @series_params %{
    "name" => "Series name", "slug" => "series-name",
    "credits" => "Credits", "order" => 0
  }
  @category_params %{
    "cfg" => @cfg, "name" => "Test Category",
    "slug" => "test-category"
  }
  @broken_params %{"cfg" => @cfg}
  @up_params %Plug.Upload{
    content_type: "image/png",
    filename: "sample.png", path: @path1
  }
  @up_params2 %Plug.Upload{
    content_type: "image/png",
    filename: "sample2.png", path: @path2
  }

  def create_category(user) do
    {:ok, category} = ImageCategory.create(@category_params, user)
    category
  end

  def create_series do
    user = Forge.saved_user(TestRepo)
    category = create_category(user)
    series_params = Map.put(@series_params, "image_category_id", category.id)
    {:ok, series} = ImageSeries.create(series_params, user)
    series
  end

  test "new" do
    category = create_category(Forge.saved_user(TestRepo))
    conn =
      :get
      |> call("/admin/images/series/new/#{category.id}")
      |> with_user
      |> send_request
    assert html_response(conn, 200) =~ "New image series"
  end

  test "edit" do
    series = create_series
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

  test "create (post) w/params" do
    user = Forge.saved_user(TestRepo)
    category = create_category(user)
    series_params =
      @series_params
      |> Map.put("creator_id", user.id)
      |> Map.put("image_category_id", category.id)
    conn =
      :post
      |> call("/admin/images/series/", %{"imageseries" => series_params})
      |> with_user(user)
      |> send_request
    assert redirected_to(conn, 302) =~ "/admin/images"
    assert get_flash(conn, :notice) == "Image series created"
  end

  test "update (post) w/params" do
    user = Forge.saved_user(TestRepo)
    category = create_category(user)

    series_params =
      @series_params
      |> Map.put("creator_id", user.id)
      |> Map.put("image_category_id", category.id)
    {:ok, series} = ImageSeries.create(series_params, user)

    conn =
      :patch
      |> call("/admin/images/series/#{series.id}",
              %{"imageseries" => series_params})
      |> with_user
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/images"
    assert get_flash(conn, :notice) == "Image series updated"
  end

  test "delete_confirm" do
    series = create_series
    conn =
      :get
      |> call("/admin/images/series/#{series.id}/delete")
      |> with_user
      |> send_request
    assert html_response(conn, 200) =~ "Delete image series: Series name"
  end

  test "delete" do
    series = create_series
    conn =
      :delete
      |> call("/admin/images/series/#{series.id}")
      |> with_user
      |> send_request
    assert redirected_to(conn, 302) =~ "/admin/images"
    assert get_flash(conn, :notice) == "Image series deleted"
  end

  test "upload" do
    series = create_series
    conn =
      :get
      |> call("/admin/images/series/#{series.id}/upload")
      |> with_user
      |> send_request

    assert html_response(conn, 200)
           =~ "Upload to this image series &raquo; <strong>Series name</strong>"
  end

  test "upload_post" do
    user = Forge.saved_user(TestRepo)
    category = create_category(user)
    series_params =
      @series_params
      |> Map.put("creator_id", user.id)
      |> Map.put("image_category_id", category.id)
    {:ok, series} = ImageSeries.create(series_params, user)
    conn =
      :post
      |> call("/admin/images/series/#{series.id}/upload",
              %{"id" => series.id, "image" => @up_params})
      |> with_user(user)
      |> as_json
      |> send_request
    assert json_response(conn, 200) == %{"status" => "200"}
  end

  test "sort" do
    File.rm_rf!(Brando.config(:media_path))
    File.mkdir_p!(Brando.config(:media_path))
    user = Forge.saved_user(TestRepo)
    category = create_category(user)
    series_params =
      @series_params
      |> Map.put("creator_id", user.id)
      |> Map.put("image_category_id", category.id)
    {:ok, series} = ImageSeries.create(series_params, user)

    conn =
      :post
      |> call("/admin/images/series/#{series.id}/upload",
              %{"id" => series.id, "image" => @up_params})
      |> with_user(user)
      |> as_json
      |> send_request

    assert conn.status == 200
    conn =
      :post
      |> call("/admin/images/series/#{series.id}/upload",
              %{"id" => series.id, "image" => @up_params2})
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
           =~ "<img src=\"/media/images/test-category/series-name/thumb/sample-optimized.png\" />"

    series = Brando.repo.preload(series, :images)
    [img1, img2] = series.images

    conn =
      :post
      |> call("/admin/images/series/#{series.id}/sort",
              %{"order" => [to_string(img2.id), to_string(img1.id)]})
      |> with_user(user)
      |> as_json
      |> send_request

    assert conn.status
           == 200
    assert conn.path_info
           == ["admin", "images", "series", "#{series.id}", "sort"]
    assert json_response(conn, 200)
           == %{"status" => "200"}

    series =
      ImageSeries
      |> Ecto.Query.preload([:images])
      |> Brando.repo.get_by!(id: series.id)

    [img1, img2] = series.images
    case img1.image.path do
      "images/test-category/series-name/sample.png" -> assert img1.sequence > img2.sequence
      "images/test-category/series-name/sample2.png" -> assert img1.sequence < img2.sequence
    end
  end

  test "configure get" do
    series = create_series()
    conn =
      :get
      |> call("/admin/images/series/#{series.id}/configure")
      |> with_user
      |> send_request
    assert html_response(conn, 200) =~ "Configure image series"
  end

  test "configure patch" do
    series = create_series()
    conn =
      :patch
      |> call("/admin/images/series/#{series.id}/configure",
              %{"id" => series.id, "imageseriesconfig" => @cfg_changed})
      |> with_user
      |> send_request

    assert redirected_to(conn, 302) =~ "/admin/images"
    assert get_flash(conn, :notice) == "Image series configured"
  end
end

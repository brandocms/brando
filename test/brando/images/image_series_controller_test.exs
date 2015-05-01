#Code.require_file("router_helper.exs", Path.join([__DIR__, "..", ".."]))

defmodule Brando.ImageSeries.ControllerTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  use Plug.Test
  use RouterHelper
  alias Brando.ImageSeries
  alias Brando.ImageCategory
  alias Brando.User
  alias Brando.Type.ImageConfig

  @user_params %{"avatar" => nil, "role" => ["2", "4"],
                 "email" => "fanogigyni@gmail.com", "full_name" => "Nita Bond",
                 "password" => "finimeze", "status" => "1",
                 "submit" => "Submit", "username" => "zabuzasixu"}
  @series_params %{"name" => "Series name", "slug" => "series-name", "credits" => "Credits", "order" => 0, "creator_id" => 1}
  @category_params %{"cfg" => %ImageConfig{}, "creator_id" => 1, "name" => "Test Category", "slug" => "test-category"}
  @broken_params %{"cfg" => %ImageConfig{}, "creator_id" => 1}
  @up_params %Plug.Upload{content_type: "image/png", filename: "sample.png", path: "#{Path.expand("../../", __DIR__)}/fixtures/sample.png"}
  @up_params2 %Plug.Upload{content_type: "image/png", filename: "sample2.png", path: "#{Path.expand("../../", __DIR__)}/fixtures/sample2.png"}

  def create_user do
    {:ok, user} = User.create(@user_params)
    user
  end

  def create_category(user) do
    {:ok, category} = ImageCategory.create(@category_params, user)
    category
  end

  def create_series do
    user = create_user
    category = create_category(user)
    series_params = Map.put(@series_params, "image_category_id", category.id)
    {:ok, series} = ImageSeries.create(series_params, user)
    series
  end

  test "new" do
    category = create_category(create_user)
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/bilder/serier/ny/#{category.id}")
    assert html_response(conn, 200) =~ "Ny bildeserie"
  end

  test "edit" do
    series = create_series
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/bilder/serier/#{series.id}/endre")
    assert html_response(conn, 200) =~ "Endre bildeserie"
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/bilder/serier/1234/endre")
    assert html_response(conn, 404)
  end

  test "create (post) w/params" do
    user = create_user
    category = create_category(user)
    series_params =
      @series_params
      |> Map.put("creator_id", user.id)
      |> Map.put("image_category_id", category.id)
    conn = call_with_custom_user(RouterHelper.TestRouter, :post, "/admin/bilder/serier/", %{"imageseries" => series_params}, user: user)
    assert redirected_to(conn, 302) =~ "/admin/bilder"
    assert get_flash(conn, :notice) == "Bildeserie opprettet."
  end

  test "create (post) w/erroneus params" do
    user = create_user
    series_params = Map.put(@series_params, "creator_id", user.id)
    conn = call_with_user(RouterHelper.TestRouter, :post, "/admin/bilder/serier/", %{"imageseries" => series_params})
    assert html_response(conn, 200) =~ "Ny bildeserie"
    assert get_flash(conn, :error) == "Feil i skjema"
  end

  test "update (post) w/params" do
    user = create_user
    category = create_category(user)
    series_params =
      @series_params
      |> Map.put("creator_id", user.id)
      |> Map.put("image_category_id", category.id)
    {:ok, series} = ImageSeries.create(series_params, user)
    conn = call_with_user(RouterHelper.TestRouter, :patch, "/admin/bilder/serier/#{series.id}", %{"imageseries" => series_params})
    assert redirected_to(conn, 302) =~ "/admin/bilder"
    assert get_flash(conn, :notice) == "Serie oppdatert."
  end

  test "delete_confirm" do
    series = create_series
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/bilder/serier/#{series.id}/slett")
    assert html_response(conn, 200) =~ "Slett bildeserie: Series name"
  end

  test "delete" do
    series = create_series
    conn = call_with_user(RouterHelper.TestRouter, :delete, "/admin/bilder/serier/#{series.id}")
    assert redirected_to(conn, 302) =~ "/admin/bilder"
    assert get_flash(conn, :notice) == "bildeserie Series name – 0 bilde(r). slettet."
  end

  test "upload" do
    series = create_series
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/bilder/serier/#{series.id}/last-opp")
    assert html_response(conn, 200) =~ "Last opp"
  end

  test "upload_post" do
    user = create_user
    category = create_category(user)
    series_params =
      @series_params
      |> Map.put("creator_id", user.id)
      |> Map.put("image_category_id", category.id)
    {:ok, series} = ImageSeries.create(series_params, user)
    conn = json_with_custom_user(RouterHelper.TestRouter, :post, "/admin/bilder/serier/#{series.id}/last-opp", %{"id" => series.id, "image" => @up_params}, user: user)
    assert json_response(conn, 200) == %{"status" => "200"}
  end

  test "sort" do
    File.rm_rf!(Path.join([Mix.Project.app_path, "tmp", "media"]))
    File.mkdir_p!(Path.join([Mix.Project.app_path, "tmp", "media"]))
    user = create_user
    category = create_category(user)
    series_params =
      @series_params
      |> Map.put("creator_id", user.id)
      |> Map.put("image_category_id", category.id)
    {:ok, series} = ImageSeries.create(series_params, user)

    conn = json_with_custom_user(RouterHelper.TestRouter, :post, "/admin/bilder/serier/#{series.id}/last-opp", %{"id" => series.id, "image" => @up_params}, user: user)
    assert conn.status == 200
    conn = json_with_custom_user(RouterHelper.TestRouter, :post, "/admin/bilder/serier/#{series.id}/last-opp", %{"id" => series.id, "image" => @up_params2}, user: user)
    assert conn.status == 200

    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/bilder/serier/#{series.id}/sorter")
    assert conn.status == 200
    assert html_response(conn, 200) =~ "<img src=\"/media/images/default/thumb/sample.png\" />"

    series = Brando.repo.preload(series, :images)
    [img1, img2] = series.images

    conn = json_with_custom_user(RouterHelper.TestRouter, :post, "/admin/bilder/serier/#{series.id}/sorter", %{"order" => [to_string(img2.id), to_string(img1.id)]}, user: user)
    assert conn.status == 200
    assert conn.path_info == ["admin", "bilder", "serier", "#{series.id}", "sorter"]
    assert json_response(conn, 200) == %{"status" => "200"}

    series = ImageSeries.get(id: series.id)
    series = Brando.repo.preload(series, :images)

    [img1, img2] = series.images
    case img1.image.path do
      "images/default/sample.png" -> assert img1.sequence > img2.sequence
      "images/default/sample2.png" -> assert img1.sequence < img2.sequence
    end
  end
end
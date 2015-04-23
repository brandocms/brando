Code.require_file("router_helper.exs", Path.join([__DIR__, "..", ".."]))

defmodule Brando.ImageSeries.ControllerTest do
  use ExUnit.Case
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
    assert conn.status == 200
    assert conn.path_info == ["admin", "bilder", "serier", "ny", "#{category.id}"]
    assert conn.private.phoenix_layout == {Brando.Admin.LayoutView, "admin.html"}
  end

  test "edit" do
    series = create_series
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/bilder/serier/#{series.id}/endre")
    assert conn.status == 200
    assert conn.path_info == ["admin", "bilder", "serier", "#{series.id}", "endre"]
    assert conn.private.phoenix_layout == {Brando.Admin.LayoutView, "admin.html"}
    assert conn.resp_body =~ "Endre bildeserie"
    assert conn.resp_body =~ "value=\"series-name\""
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/bilder/serier/1234/endre")
    assert conn.status == 404
  end

  test "create (post) w/params" do
    user = create_user
    category = create_category(user)
    series_params = Map.put(@series_params, "creator_id", user.id)
    series_params = Map.put(series_params, "image_category_id", category.id)
    conn = call_with_custom_user(RouterHelper.TestRouter, :post, "/admin/bilder/serier/", %{"imageseries" => series_params}, user: user)
    assert conn.status == 302
    assert get_resp_header(conn, "Location") == ["/admin/bilder"]
    assert conn.path_info == ["admin", "bilder", "serier"]
    assert conn.private.phoenix_layout == {Brando.Admin.LayoutView, "admin.html"}
    %{phoenix_flash: flash} = conn.private
    assert flash == %{"notice" => "Bildeserie opprettet."}
  end

  test "create (post) w/erroneus params" do
    user = create_user
    series_params = Map.put(@series_params, "creator_id", user.id)
    conn = call_with_user(RouterHelper.TestRouter, :post, "/admin/bilder/serier/", %{"imageseries" => series_params})
    assert conn.status == 200
    assert conn.path_info == ["admin", "bilder", "serier"]
    assert conn.private.phoenix_layout == {Brando.Admin.LayoutView, "admin.html"}
    %{phoenix_flash: flash} = conn.private
    assert flash == %{"error" => "Feil i skjema"}
  end

  test "update (post) w/params" do
    user = create_user
    category = create_category(user)
    series_params = Map.put(@series_params, "creator_id", user.id)
    series_params = Map.put(series_params, "image_category_id", category.id)
    {:ok, series} = ImageSeries.create(series_params, user)
    conn = call_with_user(RouterHelper.TestRouter, :patch, "/admin/bilder/serier/#{series.id}", %{"imageseries" => series_params})
    assert conn.status == 302
    assert get_resp_header(conn, "Location") == ["/admin/bilder"]
    assert conn.path_info == ["admin", "bilder", "serier", "#{series.id}"]
    assert conn.private.phoenix_layout == {Brando.Admin.LayoutView, "admin.html"}
    %{phoenix_flash: flash} = conn.private
    assert flash == %{"notice" => "Serie oppdatert."}
  end

  test "delete_confirm" do
    series = create_series
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/bilder/serier/#{series.id}/slett")
    assert conn.status == 200
    assert conn.path_info == ["admin", "bilder", "serier", "#{series.id}", "slett"]
    assert conn.resp_body =~ "Slett bildeserie: Series name"
  end

  test "delete" do
    series = create_series
    conn = call_with_user(RouterHelper.TestRouter, :delete, "/admin/bilder/serier/#{series.id}")
    assert conn.status == 302
    assert conn.path_info == ["admin", "bilder", "serier", "#{series.id}"]
    assert conn.private.phoenix_layout == {Brando.Admin.LayoutView, "admin.html"}
    assert get_resp_header(conn, "Location") == ["/admin/bilder"]
    %{phoenix_flash: flash} = conn.private
    assert flash == %{"notice" => "bildeserie Series name – 0 bilde(r). slettet."}
  end

  test "upload" do
    series = create_series
    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/bilder/serier/#{series.id}/last-opp")
    assert conn.status == 200
    assert conn.path_info == ["admin", "bilder", "serier", "#{series.id}", "last-opp"]
    assert conn.private.phoenix_layout == {Brando.Admin.LayoutView, "admin.html"}
  end

  test "upload_post" do
    user = create_user
    category = create_category(user)
    series_params = Map.put(@series_params, "creator_id", user.id)
    series_params = Map.put(series_params, "image_category_id", category.id)
    {:ok, series} = ImageSeries.create(series_params, user)
    conn = json_with_custom_user(RouterHelper.TestRouter, :post, "/admin/bilder/serier/#{series.id}/last-opp", %{"id" => series.id, "image" => @up_params}, user: user)
    assert conn.status == 200
    assert conn.path_info == ["admin", "bilder", "serier", "#{series.id}", "last-opp"]
    assert conn.resp_body == "{\"status\":\"200\"}"
    assert conn.private.phoenix_layout == {Brando.Admin.LayoutView, "admin.html"}
  end

  test "sort" do
    File.rm_rf!(Path.join([Mix.Project.app_path, "tmp", "media"]))
    File.mkdir_p!(Path.join([Mix.Project.app_path, "tmp", "media"]))
    user = create_user
    category = create_category(user)
    series_params = Map.put(@series_params, "creator_id", user.id)
    series_params = Map.put(series_params, "image_category_id", category.id)
    {:ok, series} = ImageSeries.create(series_params, user)

    conn = json_with_custom_user(RouterHelper.TestRouter, :post, "/admin/bilder/serier/#{series.id}/last-opp", %{"id" => series.id, "image" => @up_params}, user: user)
    assert conn.status == 200
    conn = json_with_custom_user(RouterHelper.TestRouter, :post, "/admin/bilder/serier/#{series.id}/last-opp", %{"id" => series.id, "image" => @up_params2}, user: user)
    assert conn.status == 200

    conn = call_with_user(RouterHelper.TestRouter, :get, "/admin/bilder/serier/#{series.id}/sorter")
    assert conn.status == 200
    assert conn.path_info == ["admin", "bilder", "serier", "#{series.id}", "sorter"]
    assert conn.private.phoenix_layout == {Brando.Admin.LayoutView, "admin.html"}
    assert conn.resp_body =~ "<img src=\"/media/images/default/thumb/sample.png\" /></li>"

    series = Brando.repo.preload(series, :images)
    [img1, img2] = series.images

    conn = json_with_custom_user(RouterHelper.TestRouter, :post, "/admin/bilder/serier/#{series.id}/sorter", %{"order" => [to_string(img2.id), to_string(img1.id)]}, user: user)
    assert conn.status == 200
    assert conn.path_info == ["admin", "bilder", "serier", "#{series.id}", "sorter"]
    assert conn.resp_body == "{\"status\":\"200\"}"

    series = ImageSeries.get(id: series.id)
    series = Brando.repo.preload(series, :images)

    [img1, img2] = series.images
    case img1.image.path do
      "images/default/sample.png" -> assert img1.order > img2.order
      "images/default/sample2.png" -> assert img1.order < img2.order
    end
  end
end
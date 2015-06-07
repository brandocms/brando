#Code.require_file("router_helper.exs", Path.join([__DIR__, "..", ".."]))

defmodule Brando.ImageSeries.ControllerTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  use Plug.Test
  use RouterHelper
  alias Brando.ImageSeries
  alias Brando.ImageCategory
  alias Brando.Type.ImageConfig

  @series_params %{"name" => "Series name", "slug" => "series-name", "credits" => "Credits", "order" => 0}
  @category_params %{"cfg" => %ImageConfig{}, "name" => "Test Category", "slug" => "test-category"}
  @broken_params %{"cfg" => %ImageConfig{}, }
  @up_params %Plug.Upload{content_type: "image/png", filename: "sample.png", path: "#{Path.expand("../../", __DIR__)}/fixtures/sample.png"}
  @up_params2 %Plug.Upload{content_type: "image/png", filename: "sample2.png", path: "#{Path.expand("../../", __DIR__)}/fixtures/sample2.png"}

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
      call(:get, "/admin/bilder/serier/ny/#{category.id}")
      |> with_user
      |> send_request
    assert html_response(conn, 200) =~ "Ny bildeserie"
  end

  test "edit" do
    series = create_series
    conn =
      call(:get, "/admin/bilder/serier/#{series.id}/endre")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Endre bildeserie"

    assert_raise Plug.Conn.WrapperError, fn ->
      call(:get, "/admin/bilder/serier/1234/endre")
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
      call(:post, "/admin/bilder/serier/", %{"imageseries" => series_params})
      |> with_user(user)
      |> send_request
    assert redirected_to(conn, 302) =~ "/admin/bilder"
    assert get_flash(conn, :notice) == "Bildeserie opprettet."
  end

  test "create (post) w/erroneus params" do
    user = Forge.saved_user(TestRepo)
    series_params = Map.put(@series_params, "creator_id", user.id)
    conn =
      call(:post, "/admin/bilder/serier/", %{"imageseries" => series_params})
      |> with_user
      |> send_request
    assert html_response(conn, 200) =~ "Ny bildeserie"
    assert get_flash(conn, :error) == "Feil i skjema"
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
      call(:patch, "/admin/bilder/serier/#{series.id}", %{"imageseries" => series_params})
      |> with_user
      |> send_request
    assert redirected_to(conn, 302) =~ "/admin/bilder"
    assert get_flash(conn, :notice) == "Serie oppdatert."
  end

  test "delete_confirm" do
    series = create_series
    conn =
      call(:get, "/admin/bilder/serier/#{series.id}/slett")
      |> with_user
      |> send_request
    assert html_response(conn, 200) =~ "Slett bildeserie: Series name"
  end

  test "delete" do
    series = create_series
    conn =
      call(:delete, "/admin/bilder/serier/#{series.id}")
      |> with_user
      |> send_request
    assert redirected_to(conn, 302) =~ "/admin/bilder"
    assert get_flash(conn, :notice) == "bildeserie Series name – 0 bilde(r). slettet."
  end

  test "upload" do
    series = create_series
    conn =
      call(:get, "/admin/bilder/serier/#{series.id}/last-opp")
      |> with_user
      |> send_request
    assert html_response(conn, 200) =~ "Last opp"
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
      call(:post, "/admin/bilder/serier/#{series.id}/last-opp", %{"id" => series.id, "image" => @up_params})
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
      call(:post, "/admin/bilder/serier/#{series.id}/last-opp", %{"id" => series.id, "image" => @up_params})
      |> with_user(user)
      |> as_json
      |> send_request

    assert conn.status == 200
    conn =
      call(:post, "/admin/bilder/serier/#{series.id}/last-opp", %{"id" => series.id, "image" => @up_params2}, user: user)
      |> with_user(user)
      |> as_json
      |> send_request
    assert conn.status == 200

    conn =
      call(:get, "/admin/bilder/serier/#{series.id}/sorter")
      |> with_user
      |> send_request
    assert conn.status == 200
    assert html_response(conn, 200) =~ "<img src=\"/media/images/default/thumb/sample.png\" />"

    series = Brando.repo.preload(series, :images)
    [img1, img2] = series.images

    conn =
      call(:post, "/admin/bilder/serier/#{series.id}/sorter", %{"order" => [to_string(img2.id), to_string(img1.id)]})
      |> with_user(user)
      |> as_json
      |> send_request
    assert conn.status == 200
    assert conn.path_info == ["admin", "bilder", "serier", "#{series.id}", "sorter"]
    assert json_response(conn, 200) == %{"status" => "200"}

    series =
      ImageSeries
      |> Ecto.Query.preload([:images])
      |> Brando.repo.get_by!(id: series.id)

    [img1, img2] = series.images
    case img1.image.path do
      "images/default/sample.png" -> assert img1.sequence > img2.sequence
      "images/default/sample2.png" -> assert img1.sequence < img2.sequence
    end
  end
end
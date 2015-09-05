defmodule Brando.Image.ControllerTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  use Plug.Test
  use RouterHelper
  alias Brando.Image
  alias Brando.ImageSeries
  alias Brando.ImageCategory
  alias Brando.Type.ImageConfig

  @path "#{Path.expand("../../", __DIR__)}/fixtures/sample.png"
  @series_params %{"name" => "Series name", "slug" => "series-name",
                   "credits" => "Credits", "order" => 0}
  @category_params %{"cfg" => %ImageConfig{}, "name" => "Test Category",
                     "slug" => "test-category"}
  @up_params %Plug.Upload{content_type: "image/png",
                          filename: "sample.png", path: @path}

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

  test "index" do
    create_series
    conn =
      :get
      |> call("/admin/images/")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Oversikt"
    assert html_response(conn, 200) =~ "Test category"
    assert html_response(conn, 200) =~ "Series name"
  end

  test "delete_selected" do
    # upload first
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

    q = from(m in Image,
             select: m.id,
             where: m.image_series_id == ^series.id,
             order_by: m.sequence)
    images = q |> Brando.repo.all

    conn =
      :post
      |> call("/admin/images/delete-selected-images", %{"ids" => images})
      |> with_user(user)
      |> as_json
      |> send_request

    assert json_response(conn, 200) == %{"status" => "200", "ids" => images}

    images = q |> Brando.repo.all

    assert images == []
  end
end

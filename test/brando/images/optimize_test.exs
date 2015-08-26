defmodule Brando.Image.OptimizeTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  use Plug.Test
  use RouterHelper
  import Brando.Images.Optimize
  alias Brando.Image
  alias Brando.ImageSeries
  alias Brando.ImageCategory
  alias Brando.Type.ImageConfig

  @series_params %{"name" => "Series name", "slug" => "series-name", "credits" => "Credits", "order" => 0}
  @category_params %{"cfg" => %ImageConfig{}, "name" => "Test Category", "slug" => "test-category"}
  @up_params %Plug.Upload{content_type: "image/png", filename: "sample.png", path: "#{Path.expand("../../", __DIR__)}/fixtures/sample.png"}
  @up_params2 %Plug.Upload{content_type: "image/jpeg", filename: "sample.jpg", path: "#{Path.expand("../../", __DIR__)}/fixtures/sample.jpg"}

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

  test "optimize" do
    # upload first
    user = Forge.saved_user(TestRepo)
    category = create_category(user)
    series_params =
      @series_params
      |> Map.put("creator_id", user.id)
      |> Map.put("image_category_id", category.id)
    {:ok, series} = ImageSeries.create(series_params, user)

    call(:post, "/admin/images/series/#{series.id}/upload", %{"id" => series.id, "image" => @up_params})
    |> with_user(user)
    |> as_json
    |> send_request

    image = Brando.repo.all(Image) |> List.first
    {:ok, optimized_image} = optimize({:ok, image.image})

    assert optimized_image.optimized
    assert File.exists?(Brando.Images.Utils.media_path("images/default/large/sample.png"))
    assert File.exists?(Brando.Images.Utils.media_path("images/default/large/sample-optimized.png"))

    Brando.repo.delete(image)

    call(:post, "/admin/images/series/#{series.id}/upload", %{"id" => series.id, "image" => @up_params2})
    |> with_user(user)
    |> as_json
    |> send_request

    image = Brando.repo.all(Image) |> List.first
    {:ok, optimized_image} = optimize({:ok, image.image})

    refute optimized_image.optimized
    assert File.exists?(Brando.Images.Utils.media_path("images/default/large/sample.jpg"))
    refute File.exists?(Brando.Images.Utils.media_path("images/default/large/sample-optimized.jpg"))
  end
end
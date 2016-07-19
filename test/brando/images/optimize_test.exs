defmodule Brando.Image.OptimizeTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  use Plug.Test
  use RouterHelper

  import Brando.Images.Optimize
  import Brando.Images.Utils, only: [media_path: 1]

  alias Brando.Image
  alias Brando.Factory

  setup do
    user = Factory.insert(:user)
    category = Factory.insert(:image_category, creator: user)
    series = Factory.insert(:image_series, creator: user, image_category: category)
    {:ok, %{user: user, category: category, series: series}}
  end

  test "optimize", %{series: series, user: user} do
    up_params = Factory.build(:plug_upload)
    up_params_jpeg = Factory.build(:plug_upload_jpeg)

    :post
    |> call("/admin/images/series/#{series.id}/upload", %{"id" => series.id, "image" => up_params})
    |> with_user(user)
    |> as_json
    |> send_request

    image =
      Image
      |> Brando.repo.all
      |> List.first

    {:ok, optimized_image} = optimize({:ok, image.image})

    assert optimized_image.optimized

    assert File.exists?(media_path("portfolio/test-category/test-series/small/sample.png"))
    assert File.exists?(media_path("portfolio/test-category/test-series/small/sample-optimized.png"))

    Brando.repo.delete(image)

    :post
    |> call("/admin/images/series/#{series.id}/upload", %{"id" => series.id, "image" => up_params_jpeg})
    |> with_user(user)
    |> as_json
    |> send_request

    image =
      Image
      |> Brando.repo.all
      |> List.first

    {:ok, optimized_image} = optimize({:ok, image.image})

    refute optimized_image.optimized
    assert File.exists?(media_path("portfolio/test-category/test-series/small/sample.jpg"))
    refute File.exists?(media_path("portfolio/test-category/test-series/small/sample-optimized.jpg"))
  end
end

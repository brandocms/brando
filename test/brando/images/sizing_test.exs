defmodule Brando.Images.Processing.SizingTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase

  import Brando.Images.Operations.Sizing
  alias Brando.Images.ConversionParameters

  test "add_crop_dimensions" do
    cp =
      %ConversionParameters{
        crop: true,
        original_width: 2560,
        original_height: 1600,
        size_cfg: %{"crop" => true, "quality" => 70, "size" => "500x500"}
      }

    new_cp = add_crop_dimensions(cp)
    assert new_cp.crop_height == 500
    assert new_cp.crop_width == 500
  end

  test "add_resize_dimensions" do
    cp =
      %ConversionParameters{
        crop: true,
        original_width: 2560,
        original_height: 1600,
        size_cfg: %{"crop" => true, "quality" => 70, "size" => "500x500"}
      } |> add_crop_dimensions()

    cp = add_resize_dimensions(cp)
    assert cp.resize_width == 800
    assert cp.resize_height == 500

    cp = Map.merge(cp, %{crop_width: 2560, crop_height: 1600})
    cp = add_resize_dimensions(cp)
    assert cp.resize_width == 2560
    assert cp.resize_height == 1600

    cp = Map.merge(cp, %{crop_width: 3000, crop_height: 2000})
    cp = add_resize_dimensions(cp)
    assert cp.resize_width == 3200
    assert cp.resize_height == 2000

    cp = Map.merge(cp, %{original_width: 300, original_height: 300, crop_width: 500, crop_height: 500})
    cp = add_resize_dimensions(cp)
    assert cp.resize_width == 500
    assert cp.resize_height == 500

    cp = Map.merge(cp, %{crop_width: 700, crop_height: 500})
    cp = add_resize_dimensions(cp)
    assert cp.resize_width == 700
    assert cp.resize_height == 700
  end

  test "add_anchor" do
  #   focal = %{"x" => 100, "y" => 100}
  #   original_width = 1000
  #   original_height = 500
  #   resized_width = 500
  #   resized_height = 250
  #   crop_width = 50
  #   crop_height = 50

  #   assert get_anchor(focal, original_width, original_height, resized_width, resized_height, crop_width, crop_height)
  #          == %{x: 450, y: 200}

    cp =
      %ConversionParameters{
        crop: true,
        original_width: 1000,
        original_height: 500,
        quality: 100,
        focal_point: %{"x" => 100, "y" => 100},
        size_cfg: %{"crop" => true, "quality" => 70, "size" => "50x200"}
      }
      |> add_crop_dimensions()
      |> add_resize_dimensions()
      |> add_anchor()

    require Logger
    Logger.error inspect cp, pretty: true

  end

  # test "get_original_focal_point" do
  #   focal = %{"x" => 50, "y" => 50}
  #   original_width = 1000
  #   original_height = 500
  #   assert get_original_focal_point(focal, original_width, original_height) == %{x: 500.0, y: 250.0}

  #   focal = %{"x" => 0, "y" => 50}
  #   assert get_original_focal_point(focal, original_width, original_height) == %{x: 0, y: 250.0}
  # end

  # test "transform_focal_point" do
  #   original_focal_point = %{x: 500.0, y: 250.0}
  #   original_width = 1000
  #   original_height = 500
  #   resized_width = 1000
  #   resized_height = 500
  #   assert transform_focal_point(original_focal_point, original_width, original_height, resized_width, resized_height)
  #          == %{x: 500.0, y: 250.0}

  #   resized_width = 500
  #   resized_height = 250
  #   assert transform_focal_point(original_focal_point, original_width, original_height, resized_width, resized_height)
  #          == %{x: 250.0, y: 125.0}
  # end

  # test "get_anchor" do
  #   focal = %{"x" => 100, "y" => 100}
  #   original_width = 1000
  #   original_height = 500
  #   resized_width = 500
  #   resized_height = 250
  #   crop_width = 50
  #   crop_height = 50

  #   assert get_anchor(focal, original_width, original_height, resized_width, resized_height, crop_width, crop_height)
  #          == %{x: 450, y: 200}
  # end

  # test "focaled crop" do
  #   focal = %{"x" => 70, "y" => 50}
  #   original_width = 2560
  #   original_height = 1600

  #   {resized_width, resized_height} = calculate_resize_dimensions(original_width, original_height, %{"crop" => true, "quality" => 70, "size" => "500x500"})

  #   crop_width = 300
  #   crop_height = 1600

  #   anchor = get_anchor(focal, original_width, original_height, resized_width, resized_height, crop_width, crop_height)

  #   res = process_img("#{resized_width}x#{resized_height}", "#{crop_width}x#{crop_height}+#{anchor.x}+#{anchor.y}")
  #   require Logger
  #   Logger.error inspect res, pretty: true
  # end

  # test "calculate_geometry_with_focal" do
  #   focal = %{"x" => 50, "y" => 50}
  #   width = 2560
  #   height = 1600
  #   cfg = %{"crop" => true, "quality" => 70, "size" => "500x750"}
  #   geo = calculate_geometry_with_focal(focal, width, height, cfg)

  #   require Logger
  #   Logger.error inspect geo
  #   res = process_img(geo, cfg)

  #   Logger.error inspect res


  #   # focal = %{"x" => 50, "y" => 50}
  #   # width = 2560
  #   # height = 1600
  #   # cfg = %{"crop" => true, "quality" => 70, "size" => "25x25>"}

  #   # geo = calculate_geometry_with_focal(focal, width, height, cfg)
  # end
end

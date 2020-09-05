defmodule Brando.Images.Processing.SizingTest do
  use ExUnit.Case
  use Brando.ConnCase
  use BrandoIntegration.TestCase

  import Brando.Images.Operations.Sizing
  alias Brando.Images.ConversionParameters

  test "get_size_cfg_orientation" do
    size_cfg = %{
      "portrait" => %{"crop" => true, "quality" => 70, "size" => "200x500"},
      "landscape" => %{"crop" => true, "quality" => 70, "size" => "500x200"}
    }

    assert get_size_cfg_orientation(size_cfg, 200, 500) == %{
             "crop" => true,
             "quality" => 70,
             "size" => "200x500"
           }

    assert get_size_cfg_orientation(size_cfg, 500, 200) == %{
             "crop" => true,
             "quality" => 70,
             "size" => "500x200"
           }
  end

  test "add_crop_dimensions" do
    cp = %ConversionParameters{
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
      }
      |> add_crop_dimensions()

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

    cp =
      Map.merge(cp, %{
        original_width: 300,
        original_height: 300,
        crop_width: 500,
        crop_height: 500
      })

    cp = add_resize_dimensions(cp)
    assert cp.resize_width == 500
    assert cp.resize_height == 500

    cp = Map.merge(cp, %{crop_width: 700, crop_height: 500})
    cp = add_resize_dimensions(cp)
    assert cp.resize_width == 700
    assert cp.resize_height == 700
  end

  test "add_anchor" do
    focal = %{x: 100, y: 100}
    size_cfg = %{"crop" => true, "quality" => 70, "size" => "50x200"}

    res =
      %ConversionParameters{
        original_width: 1000,
        original_height: 500
      }
      |> cv(size_cfg, focal)

    assert res == %Brando.Images.ConversionParameters{
             anchor: %{x: 350, y: 0},
             crop: true,
             crop_height: 200,
             crop_values: %{height: 200, left: 350, top: 0, width: 50},
             crop_width: 50,
             focal_point: %{x: 100, y: 100},
             format: nil,
             id: nil,
             image: nil,
             image_dest_path: nil,
             image_dest_rel_path: nil,
             image_src_path: nil,
             original_focal_point: %{x: 1000, y: 500},
             original_height: 500,
             original_width: 1000,
             quality: 70,
             resize_height: 200,
             resize_values: %{height: 200, width: 400},
             resize_width: 400,
             size_cfg: %{"crop" => true, "quality" => 70, "size" => "50x200"},
             size_key: nil,
             transformed_focal_point: %{x: 400, y: 200}
           }
  end

  test "add_anchor smaller width than crop" do
    focal = %{x: 100, y: 100}
    size_cfg = %{"crop" => true, "quality" => 70, "size" => "50x200"}

    res =
      %ConversionParameters{
        original_width: 20,
        original_height: 500
      }
      |> cv(size_cfg, focal)

    assert res == %Brando.Images.ConversionParameters{
             anchor: %{x: 0, y: 1050},
             crop: true,
             crop_height: 200,
             crop_values: %{height: 200, left: 0, top: 1050, width: 50},
             crop_width: 50,
             focal_point: %{x: 100, y: 100},
             format: nil,
             id: nil,
             image: nil,
             image_dest_path: nil,
             image_dest_rel_path: nil,
             image_src_path: nil,
             original_focal_point: %{x: 20, y: 500},
             original_height: 500,
             original_width: 20,
             quality: 70,
             resize_height: 1250,
             resize_values: %{height: 1250, width: 50},
             resize_width: 50,
             size_cfg: %{"crop" => true, "quality" => 70, "size" => "50x200"},
             size_key: nil,
             transformed_focal_point: %{x: 50, y: 1250}
           }
  end

  test "add_values WxH" do
    focal = %{x: 50, y: 50}
    size_cfg = %{"crop" => false, "quality" => 70, "size" => "200x200"}

    res =
      %ConversionParameters{
        original_width: 500,
        original_height: 500
      }
      |> cv(size_cfg, focal)

    assert res == %Brando.Images.ConversionParameters{
             anchor: nil,
             crop: false,
             crop_height: nil,
             crop_values: nil,
             crop_width: nil,
             focal_point: %{x: 50, y: 50},
             format: nil,
             id: nil,
             image: nil,
             image_dest_path: nil,
             image_dest_rel_path: nil,
             image_src_path: nil,
             original_focal_point: nil,
             original_height: 500,
             original_width: 500,
             quality: 70,
             resize_height: nil,
             resize_values: %{height: 200, width: 200},
             resize_width: nil,
             size_cfg: %{"crop" => false, "quality" => 70, "size" => "200x200"},
             size_key: nil,
             transformed_focal_point: nil
           }
  end

  test "add_values xH" do
    focal = %{x: 50, y: 50}
    size_cfg = %{"crop" => false, "quality" => 70, "size" => "x200"}

    res =
      %ConversionParameters{
        original_width: 500,
        original_height: 500
      }
      |> cv(size_cfg, focal)

    assert res == %Brando.Images.ConversionParameters{
             anchor: nil,
             crop: false,
             crop_height: nil,
             crop_values: nil,
             crop_width: nil,
             focal_point: %{x: 50, y: 50},
             format: nil,
             id: nil,
             image: nil,
             image_dest_path: nil,
             image_dest_rel_path: nil,
             image_src_path: nil,
             original_focal_point: nil,
             original_height: 500,
             original_width: 500,
             quality: 70,
             resize_height: nil,
             resize_values: %{height: 200},
             resize_width: nil,
             size_cfg: %{"crop" => false, "quality" => 70, "size" => "x200"},
             size_key: nil,
             transformed_focal_point: nil
           }
  end

  test "add_values Wx" do
    focal = %{x: 50, y: 50}
    size_cfg = %{"crop" => false, "quality" => 70, "size" => "200x"}

    res =
      %ConversionParameters{
        original_width: 500,
        original_height: 500
      }
      |> cv(size_cfg, focal)

    assert res == %Brando.Images.ConversionParameters{
             anchor: nil,
             crop: false,
             crop_height: nil,
             crop_values: nil,
             crop_width: nil,
             focal_point: %{x: 50, y: 50},
             format: nil,
             id: nil,
             image: nil,
             image_dest_path: nil,
             image_dest_rel_path: nil,
             image_src_path: nil,
             original_focal_point: nil,
             original_height: 500,
             original_width: 500,
             quality: 70,
             resize_height: nil,
             resize_values: %{width: 200},
             resize_width: nil,
             size_cfg: %{"crop" => false, "quality" => 70, "size" => "200x"},
             size_key: nil,
             transformed_focal_point: nil
           }
  end

  test "add_values W" do
    focal = %{x: 50, y: 50}
    size_cfg = %{"crop" => false, "quality" => 70, "size" => "200"}

    res =
      %ConversionParameters{
        original_width: 500,
        original_height: 500
      }
      |> cv(size_cfg, focal)

    assert res == %Brando.Images.ConversionParameters{
             anchor: nil,
             crop: false,
             crop_height: nil,
             crop_values: nil,
             crop_width: nil,
             focal_point: %{x: 50, y: 50},
             format: nil,
             id: nil,
             image: nil,
             image_dest_path: nil,
             image_dest_rel_path: nil,
             image_src_path: nil,
             original_focal_point: nil,
             original_height: 500,
             original_width: 500,
             quality: 70,
             resize_height: nil,
             resize_values: %{width: 200},
             resize_width: nil,
             size_cfg: %{"crop" => false, "quality" => 70, "size" => "200"},
             size_key: nil,
             transformed_focal_point: nil
           }
  end

  defp cv(conversion_parameters, size_cfg, focal) do
    conversion_parameters
    |> add_size_cfg(size_cfg)
    |> add_quality()
    |> add_focal_point(focal)
    |> add_crop_flag()
    |> add_crop_dimensions()
    |> add_resize_dimensions()
    |> add_anchor()
    |> add_values()
  end
end

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

  test "add_size_cfg picks the orientation entry matching the original" do
    size_cfg = %{
      "portrait" => %{"crop" => true, "quality" => 70, "size" => "200x500"},
      "landscape" => %{"crop" => true, "quality" => 70, "size" => "500x200"}
    }

    landscape = add_size_cfg(%ConversionParameters{original_width: 2560, original_height: 1600}, size_cfg)
    assert landscape.size_cfg["size"] == "500x200"

    portrait = add_size_cfg(%ConversionParameters{original_width: 1600, original_height: 2560}, size_cfg)
    assert portrait.size_cfg["size"] == "200x500"
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

    # Not enlarged: the largest 1:1 crop a 300×200 original holds.
    small = add_crop_dimensions(%{cp | original_width: 300, original_height: 200})
    assert {small.crop_width, small.crop_height} == {200, 200}
  end

  test "fit_crop keeps a crop that fits and shrinks one that doesn't to the original" do
    assert fit_crop({400, 400}, {1200, 800}) == {400, 400}
    assert fit_crop({800, 800}, {1200, 800}) == {800, 800}
    assert fit_crop({400, 400}, {300, 200}) == {200, 200}
    assert fit_crop({1100, 1000}, {1200, 800}) == {880, 800}
    assert fit_crop({600, 338}, {200, 300}) == {200, 113}
  end

  test "processed_dimensions is what each size makes of an original" do
    portrait = {3000, 4000}
    small = {600, 400}

    for {size_cfg, expected_portrait, expected_small} <- [
          {%{"size" => "700"}, {700, 933}, {600, 400}},
          {%{"size" => "1400>"}, {1400, 1867}, {600, 400}},
          {%{"size" => "x400"}, {300, 400}, {600, 400}},
          {%{"size" => "700x400"}, {300, 400}, {600, 400}},
          {%{"size" => "300x300"}, {225, 300}, {300, 200}},
          {%{"size" => "400x400>", "crop" => true}, {400, 400}, {400, 400}},
          {%{"size" => "800x800", "crop" => true}, {800, 800}, {400, 400}},
          {%{"size" => "x300", "crop" => true, "ratio" => "3/2"}, {450, 300}, {450, 300}},
          {%{"portrait" => %{"size" => "x400"}, "landscape" => %{"size" => "700"}}, {300, 400}, {600, 400}}
        ] do
      assert processed_dimensions(size_cfg, portrait) == expected_portrait, inspect(size_cfg)
      assert processed_dimensions(size_cfg, small) == expected_small, inspect(size_cfg)
    end
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
             image_id: nil,
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

  test "add_anchor on an original narrower than the crop cuts the largest crop it holds" do
    focal = %{x: 100, y: 100}
    size_cfg = %{"crop" => true, "quality" => 70, "size" => "50x200"}

    res =
      %ConversionParameters{
        original_width: 20,
        original_height: 500
      }
      |> cv(size_cfg, focal)

    assert res == %Brando.Images.ConversionParameters{
             anchor: %{x: 0, y: 420},
             crop: true,
             crop_height: 80,
             crop_values: %{height: 80, left: 0, top: 420, width: 20},
             crop_width: 20,
             focal_point: %{x: 100, y: 100},
             format: nil,
             image_id: nil,
             image: nil,
             image_dest_path: nil,
             image_dest_rel_path: nil,
             image_src_path: nil,
             original_focal_point: %{x: 20, y: 500},
             original_height: 500,
             original_width: 20,
             quality: 70,
             resize_height: 500,
             resize_values: %{height: 500, width: 20},
             resize_width: 20,
             size_cfg: %{"crop" => true, "quality" => 70, "size" => "50x200"},
             size_key: nil,
             transformed_focal_point: %{x: 20, y: 500}
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
             image_id: nil,
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
             image_id: nil,
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
             image_id: nil,
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
             image_id: nil,
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

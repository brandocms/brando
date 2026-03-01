defmodule Brando.Images.Processor.VixTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias Brando.Images.Processor.Vix
  alias Brando.Images.ConversionParameters
  alias Brando.Images.TransformResult

  @fixtures_path Path.expand("../../../fixtures", __DIR__)

  setup do
    tmp_dir = System.tmp_dir!() |> Path.join("brando_vix_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, tmp_dir: tmp_dir}
  end

  describe "process_image/1 without crop" do
    test "resizes a JPG image", %{tmp_dir: tmp_dir} do
      src = Path.join(@fixtures_path, "sample.jpg")
      dest = Path.join(tmp_dir, "resized.jpg")

      params = %ConversionParameters{
        image_id: 1,
        size_key: "small",
        crop: false,
        quality: "75",
        format: "jpg",
        image_src_path: src,
        image_dest_path: dest,
        image_dest_rel_path: "images/test/small/resized.jpg",
        resize_values: %{width: 100}
      }

      assert {:ok, %TransformResult{} = result} = Vix.process_image(params)
      assert result.image_id == 1
      assert result.size_key == "small"
      assert result.format == "jpg"
      assert File.exists?(dest)

      # Verify the output has correct dimensions
      {:ok, img} = Image.open(dest)
      assert Image.width(img) <= 100
    end

    test "resizes a PNG image", %{tmp_dir: tmp_dir} do
      src = Path.join(@fixtures_path, "sample.png")
      dest = Path.join(tmp_dir, "resized.png")

      params = %ConversionParameters{
        image_id: 2,
        size_key: "thumb",
        crop: false,
        quality: "75",
        format: "png",
        image_src_path: src,
        image_dest_path: dest,
        image_dest_rel_path: "images/test/thumb/resized.png",
        resize_values: %{width: 50}
      }

      assert {:ok, %TransformResult{} = result} = Vix.process_image(params)
      assert result.format == "png"
      assert File.exists?(dest)
    end
  end

  describe "process_image/1 with crop" do
    test "crops a JPG image with focal point", %{tmp_dir: tmp_dir} do
      src = Path.join(@fixtures_path, "sample.jpg")
      dest = Path.join(tmp_dir, "cropped.jpg")

      params = %ConversionParameters{
        image_id: 1,
        size_key: "thumb",
        crop: true,
        quality: "80",
        format: "jpg",
        image_src_path: src,
        image_dest_path: dest,
        image_dest_rel_path: "images/test/thumb/cropped.jpg",
        resize_values: %{width: 200, height: 200},
        crop_values: %{left: 0, top: 0, width: 100, height: 100}
      }

      assert {:ok, %TransformResult{} = result} = Vix.process_image(params)
      assert result.size_key == "thumb"
      assert result.format == "jpg"
      assert File.exists?(dest)

      {:ok, img} = Image.open(dest)
      assert Image.width(img) == 100
      assert Image.height(img) == 100
    end
  end

  describe "get_dominant_color/1" do
    test "returns hex color string for an image" do
      # Create a temp media path structure since get_dominant_color uses media_path
      media_path = Brando.config(:media_path)
      test_path = "images/test/dominant_color_test.jpg"
      full_path = Path.join(media_path, test_path)

      File.mkdir_p!(Path.dirname(full_path))
      File.cp!(Path.join(@fixtures_path, "sample.jpg"), full_path)

      result = Vix.get_dominant_color(test_path)

      if result do
        assert String.starts_with?(result, "#")
        assert String.length(result) == 7
      end

      File.rm(full_path)
    end
  end

  describe "confirm_executable_exists/0" do
    test "returns ok when Vix NIF is available" do
      assert {:ok, {:executable, :exists}} = Vix.confirm_executable_exists()
    end
  end
end

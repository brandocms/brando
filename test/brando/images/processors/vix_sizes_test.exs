defmodule Brando.Images.Processor.VixSizesTest do
  # Every size geometry the config accepts, through the real pipeline:
  # Sizing works out the parameters and Vix writes the file.
  use ExUnit.Case, async: false

  import Brando.Test.Support, only: [put_test_env: 2]

  alias Brando.Images.Operation
  alias Brando.Images.Operations.Sizing
  alias Brando.Images.Size

  @originals %{
    landscape: {1200, 800},
    portrait: {800, 1200},
    square: {1000, 1000},
    phone: {3000, 4000},
    small: {300, 200},
    small_portrait: {200, 300}
  }

  # {size config, %{original => {width, height}}}
  @forms [
    # A width alone is that width, whatever the orientation; a height alone
    # that height; a box fits the image inside it. Nothing is enlarged.
    {%{"size" => "700"},
     %{
       landscape: {700, 467},
       portrait: {700, 1050},
       square: {700, 700},
       phone: {700, 933},
       small: {300, 200},
       small_portrait: {200, 300}
     }},
    {%{"size" => "700x"},
     %{landscape: {700, 467}, portrait: {700, 1050}, square: {700, 700}, small: {300, 200}, small_portrait: {200, 300}}},
    {%{"size" => "250"}, %{landscape: {250, 167}, portrait: {250, 375}, small: {250, 167}, small_portrait: {200, 300}}},
    {%{"size" => "x400"},
     %{
       landscape: {600, 400},
       portrait: {267, 400},
       square: {400, 400},
       phone: {300, 400},
       small: {300, 200},
       small_portrait: {200, 300}
     }},
    {%{"size" => "x250"}, %{landscape: {375, 250}, portrait: {167, 250}, small: {300, 200}, small_portrait: {167, 250}}},
    {%{"size" => "700x400"},
     %{landscape: {600, 400}, portrait: {267, 400}, square: {400, 400}, small: {300, 200}, small_portrait: {200, 300}}},
    {%{"size" => "700", "crop" => false},
     %{landscape: {700, 467}, portrait: {700, 1050}, square: {700, 700}, small: {300, 200}, small_portrait: {200, 300}}},
    # ">" (only shrink) is what every size does.
    {%{"size" => "400x400>"},
     %{landscape: {400, 267}, portrait: {267, 400}, square: {400, 400}, small: {300, 200}, small_portrait: {200, 300}}},
    {%{"size" => "1400>"}, %{landscape: {1200, 800}, portrait: {800, 1200}, phone: {1400, 1867}}},
    # The other flags are read past: "^" changes nothing, "%" is pixels.
    {%{"size" => "x400^"}, %{landscape: {600, 400}, portrait: {267, 400}, square: {400, 400}, small: {300, 200}}},
    {%{"size" => "50%"}, %{landscape: {50, 33}, portrait: {50, 75}, square: {50, 50}, small: {50, 33}}},
    # Cropped to the geometry around the focal point; a smaller original
    # gives the largest crop of the geometry's proportions it holds.
    {%{"size" => "400x400", "crop" => true},
     %{landscape: {400, 400}, portrait: {400, 400}, square: {400, 400}, small: {200, 200}, small_portrait: {200, 200}}},
    {%{"size" => "400x400>", "crop" => true},
     %{landscape: {400, 400}, portrait: {400, 400}, square: {400, 400}, small: {200, 200}, small_portrait: {200, 200}}},
    {%{"size" => "1100x1000", "crop" => true},
     %{landscape: {880, 800}, portrait: {800, 727}, square: {1000, 909}, phone: {1100, 1000}}},
    {%{"size" => "600", "crop" => true, "ratio" => "3/2"},
     %{landscape: {600, 400}, portrait: {600, 400}, square: {600, 400}, small: {300, 200}, small_portrait: {200, 133}}},
    {%{"size" => "600x", "crop" => true, "ratio" => "16/9"},
     %{landscape: {600, 338}, portrait: {600, 338}, square: {600, 338}, small: {300, 169}, small_portrait: {200, 113}}},
    {%{"size" => "x300", "crop" => true, "ratio" => "3/2"},
     %{landscape: {450, 300}, portrait: {450, 300}, square: {450, 300}, small: {300, 200}, small_portrait: {200, 133}}},
    # By orientation: a square counts as a landscape.
    {%{"portrait" => %{"size" => "x400"}, "landscape" => %{"size" => "700"}},
     %{landscape: {700, 467}, portrait: {267, 400}, square: {700, 700}, small: {300, 200}, small_portrait: {200, 300}}}
  ]

  setup do
    images_config = Application.get_env(:brando, Brando.Images, [])
    put_test_env(Brando.Images, Keyword.put(images_config, :processor_module, Brando.Images.Processor.Vix))

    dir = "images/vix_sizes_#{System.unique_integer([:positive])}"
    on_exit(fn -> File.rm_rf!(Brando.Images.Utils.media_path(dir)) end)

    for {name, {width, height}} <- @originals do
      file = Brando.Images.Utils.media_path("#{dir}/#{name}.jpg")
      File.mkdir_p!(Path.dirname(file))
      width |> Image.new!(height, color: [90, 120, 150]) |> Image.write!(file)
    end

    {:ok, dir: dir}
  end

  test "every geometry form is accepted by the config and processed to its size", %{dir: dir} do
    results =
      for {{size_cfg, expected}, index} <- Enum.with_index(@forms),
          {original, dimensions} <- expected do
        assert {:ok, ^size_cfg} = Size.normalize(size_cfg)
        {original, size_cfg, process(dir, original, size_cfg, index), dimensions}
      end

    assert Enum.reject(results, fn {_original, _cfg, actual, expected} -> actual == expected end) == []
  end

  test "a crop is its size, or the largest of its proportions a smaller original holds", %{dir: dir} do
    for {{width, height}, index} <-
          Enum.with_index([{273, 843}, {2217, 147}, {2460, 360}, {1508, 128}, {541, 2089}, {2177, 1307}, {739, 649}]),
        size_cfg <- [
          %{"size" => "400x400", "crop" => true},
          %{"size" => "333x177", "crop" => true},
          %{"size" => "601", "crop" => true, "ratio" => "4/3"},
          %{"size" => "x257", "crop" => true, "ratio" => "16/9"}
        ] do
      name = "odd-#{index}"
      file = Brando.Images.Utils.media_path("#{dir}/#{name}.jpg")
      if !File.exists?(file), do: width |> Image.new!(height, color: [1, 2, 3]) |> Image.write!(file)

      {crop_width, crop_height} = Sizing.get_crop_dimensions_from_cfg(size_cfg)

      {actual_width, actual_height} =
        process(dir, name, size_cfg, System.unique_integer([:positive]), {width, height}, %{x: 80, y: 20})

      if crop_width <= width and crop_height <= height do
        assert {actual_width, actual_height} == {crop_width, crop_height}
      else
        # Not enlarged: inside the original, touching it on one side, at the
        # crop's proportions give or take the rounding of the other side.
        assert actual_width <= width and actual_height <= height
        assert actual_width == width or actual_height == height
        assert_in_delta actual_width / actual_height, crop_width / crop_height, 1 / min(actual_width, actual_height)
      end
    end
  end

  test "an original stored on its side is sized and cropped upright", %{dir: dir} do
    # Stored as 1200×900 with EXIF orientation 6, recorded so on upload, and
    # shown upright as 900×1200 with a red band along the top.
    band = Image.new!(900, 300, color: [255, 0, 0])
    {:ok, upright} = Vix.Vips.Operation.join(band, Image.new!(900, 900, color: [0, 0, 255]), :VIPS_DIRECTION_VERTICAL)
    {:ok, stored} = Vix.Vips.Operation.rot(upright, :VIPS_ANGLE_D270)
    {:ok, stored} = Vix.Vips.Image.mutate(stored, &Vix.Vips.MutableImage.set(&1, "orientation", :gint, 6))
    Image.write!(stored, Brando.Images.Utils.media_path("#{dir}/sideways.jpg"))

    for {{size_cfg, expected}, index} <-
          Enum.with_index([
            {%{"size" => "700"}, {700, 933}},
            {%{"size" => "800x800", "crop" => true}, {800, 800}},
            {%{"size" => "1000x1000", "crop" => true}, {900, 900}},
            {%{"size" => "x1000", "crop" => true, "ratio" => "3/4"}, {750, 1000}},
            {%{"portrait" => %{"size" => "x400"}, "landscape" => %{"size" => "700"}}, {300, 400}}
          ]) do
      assert process(dir, "sideways", size_cfg, "sideways-#{index}", {1200, 900}) == expected, inspect(size_cfg)
    end

    # The focal point is on the upright image: at its top, the crop is the band.
    for {focal_y, color} <- [{0, :red}, {100, :blue}] do
      process(dir, "sideways", %{"size" => "900x300", "crop" => true}, "band-#{focal_y}", {1200, 900}, %{
        x: 50,
        y: focal_y
      })

      [r, _g, b] =
        Image.get_pixel!(Image.open!(Brando.Images.Utils.media_path("#{dir}/out-band-#{focal_y}/sideways.jpg")), 450, 150)

      assert if(color == :red, do: r > 200 and b < 50, else: b > 200 and r < 50)
    end
  end

  defp process(dir, original, size_cfg, index, dimensions \\ nil, focal \\ %{x: 50, y: 50}) do
    {width, height} = dimensions || @originals[original]
    path = "#{dir}/#{original}.jpg"
    out = "#{dir}/out-#{index}/#{original}.jpg"

    operation = %Operation{
      type: :jpg,
      image_id: 1,
      processed_formats: [:jpg],
      total_operations: 1,
      operation_index: 1,
      image_struct: %{path: path, focal: focal, width: width, height: height},
      filename: "#{original}.jpg",
      sized_image_path: out,
      sized_image_dir: Path.dirname(out),
      size_key: "size",
      size_cfg: size_cfg,
      user_id: nil
    }

    {:ok, _result} = Sizing.create_image_size(operation)
    image = Image.open!(Brando.Images.Utils.media_path(out))
    {Image.width(image), Image.height(image)}
  end
end

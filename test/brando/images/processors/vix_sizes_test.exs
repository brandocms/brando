defmodule Brando.Images.Processor.VixSizesTest do
  # Every size geometry the config accepts, through the real pipeline:
  # Sizing works out the parameters and Vix writes the file.
  use ExUnit.Case, async: false

  import Brando.Test.Support, only: [put_test_env: 2]

  alias Brando.Images.Operation
  alias Brando.Images.Operations.Sizing
  alias Brando.Images.Size

  @originals %{landscape: {1200, 800}, portrait: {800, 1200}, small: {300, 200}}

  # {size config, %{original => {width, height}}}
  @forms [
    # Fitted inside the geometry, enlarging a smaller original. A width alone
    # is fitted inside a square of that width.
    {%{"size" => "700"}, %{landscape: {700, 467}, portrait: {467, 700}, small: {700, 467}}},
    {%{"size" => "700x"}, %{landscape: {700, 467}, portrait: {467, 700}, small: {700, 467}}},
    {%{"size" => "x400"}, %{landscape: {600, 400}, portrait: {267, 400}, small: {600, 400}}},
    {%{"size" => "700x400"}, %{landscape: {600, 400}, portrait: {267, 400}, small: {600, 400}}},
    # Flags are read past: ">" doesn't stop enlarging, "%" is pixels.
    {%{"size" => "400x400>"}, %{landscape: {400, 267}, portrait: {267, 400}, small: {400, 267}}},
    {%{"size" => "x400^"}, %{landscape: {600, 400}, portrait: {267, 400}, small: {600, 400}}},
    {%{"size" => "50%"}, %{landscape: {50, 33}, portrait: {33, 50}, small: {50, 33}}},
    {%{"size" => "700", "crop" => false}, %{landscape: {700, 467}, portrait: {467, 700}, small: {700, 467}}},
    # Cropped to the geometry around the focal point.
    {%{"size" => "400x400", "crop" => true}, %{landscape: {400, 400}, portrait: {400, 400}, small: {400, 400}}},
    {%{"size" => "400x400>", "crop" => true}, %{landscape: {400, 400}, portrait: {400, 400}, small: {400, 400}}},
    {%{"size" => "600", "crop" => true, "ratio" => "3/2"},
     %{landscape: {600, 400}, portrait: {600, 400}, small: {600, 400}}},
    {%{"size" => "600x", "crop" => true, "ratio" => "16/9"},
     %{landscape: {600, 338}, portrait: {600, 338}, small: {600, 338}}},
    {%{"size" => "x300", "crop" => true, "ratio" => "3/2"},
     %{landscape: {450, 300}, portrait: {450, 300}, small: {450, 300}}},
    # By orientation.
    {%{"portrait" => %{"size" => "x400"}, "landscape" => %{"size" => "700"}},
     %{landscape: {700, 467}, portrait: {267, 400}, small: {700, 467}}}
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

  test "a crop covers its size whatever the original's proportions", %{dir: dir} do
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

      assert process(dir, name, size_cfg, System.unique_integer([:positive]), {width, height}, %{x: 80, y: 20}) ==
               Sizing.get_crop_dimensions_from_cfg(size_cfg)
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

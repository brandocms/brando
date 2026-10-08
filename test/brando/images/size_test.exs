defmodule Brando.Images.SizeTest do
  use ExUnit.Case, async: true

  alias Brando.Images.Size
  alias Brando.Type.ImageConfig

  describe "normalize_sizes/1" do
    test "keeps string-keyed sizes as they are" do
      sizes = %{
        "thumb" => %{"size" => "400x400>", "quality" => 75, "crop" => true},
        "small" => %{"size" => "700", "quality" => 75},
        "portrait" => %{"size" => "x900", "crop" => true, "ratio" => "2/3"}
      }

      assert {:ok, ^sizes} = Size.normalize_sizes(sizes)
    end

    test "accepts atom keys and structs, and stores them string-keyed" do
      sizes = %{
        thumb: %{size: "400x400>", quality: "75", crop: true},
        small: %Size{size: "700", quality: 70}
      }

      assert {:ok,
              %{
                "thumb" => %{"size" => "400x400>", "quality" => 75, "crop" => true},
                "small" => %{"size" => "700", "quality" => 70}
              }} = Size.normalize_sizes(sizes)
    end

    test "checks both sizes of an orientation pair" do
      pair = %{
        "portrait" => %{"size" => "300", "quality" => 70},
        "landscape" => %{"size" => "500", "quality" => 70}
      }

      assert {:ok, %{"medium" => ^pair}} = Size.normalize_sizes(%{"medium" => pair})

      assert {:error, ~s(:sizes["medium"] sets an orientation but has no "landscape" size)} =
               Size.normalize_sizes(%{"medium" => Map.delete(pair, "landscape")})

      assert {:error, ~s(:sizes["medium"] \(landscape\) has an invalid "quality" 0, expected 1–100)} =
               Size.normalize_sizes(%{"medium" => put_in(pair, ["landscape", "quality"], 0)})
    end

    test "names a mistyped key and suggests the right one" do
      assert {:error, ~s(:sizes["thumb"] has an unknown key "crp" \(did you mean "crop"?\))} =
               Size.normalize_sizes(%{"thumb" => %{"size" => "400x400", "crp" => true}})

      assert {:error, ~s(:sizes["small"] has an unknown key "qualty" \(did you mean "quality"?\))} =
               Size.normalize_sizes(%{"small" => %{"size" => "700", "qualty" => 75}})

      assert {:error, ~s(:sizes["small"] has an unknown key "width")} =
               Size.normalize_sizes(%{"small" => %{"size" => "700", "width" => 700}})
    end

    test "rejects sizes processing can't read" do
      for {entry, message} <- [
            {%{"quality" => 75}, ~s(has no "size")},
            {%{"size" => "700px"}, ~s(has an invalid "size" "700px")},
            {%{"size" => "x"}, ~s(has an invalid "size" "x")},
            {%{"size" => 700}, ~s(has an invalid "size" 700)},
            {%{"size" => "700", "quality" => 101}, ~s(has an invalid "quality" 101)},
            {%{"size" => "700", "crop" => "yes"}, ~s(has an invalid "crop" "yes")},
            {%{"size" => "700", "crop" => true, "ratio" => "3:2"}, ~s(has an invalid "ratio" "3:2")},
            {%{"size" => "700", "crop" => true}, ~s(is cropped but its "size" gives one dimension)},
            {"700", "must be a map"}
          ] do
        assert {:error, error} = Size.normalize_sizes(%{"small" => entry})
        assert error =~ ~s(:sizes["small"] ) <> message
      end
    end

    test "accepts a trailing > and rejects the other flags, saying what to use instead" do
      assert {:ok, _sizes} = Size.normalize_sizes(%{"thumb" => %{"size" => "400x400>"}, "wide" => %{"size" => "1400>"}})

      for {geometry, flag, instead} <- [
            {"400x400^", "^", ~s(to fill the geometry, use "crop" => true)},
            {"^2100x1400", "^", ~s(to fill the geometry, use "crop" => true)},
            {"400x300!", "!",
             ~s(for exact dimensions, use "crop" => true, with a "ratio" when the size gives one dimension)},
            {"50%", "%", ~s(give a width in pixels, such as "700", since a srcset needs fixed widths)},
            {"700<", "<", "sizes only shrink, so remove it"}
          ] do
        assert Size.normalize_sizes(%{"hero" => %{"size" => geometry}}) ==
                 {:error,
                  ~s(:sizes["hero"] has the "size" #{inspect(geometry)} with the ImageMagick flag "#{flag}", which isn't supported: #{instead})}
      end

      assert {:error, ~s(:sizes["medium"] \(portrait\) has the "size" "x900^") <> _rest} =
               Size.normalize_sizes(%{
                 "medium" => %{"portrait" => %{"size" => "x900^"}, "landscape" => %{"size" => "1100"}}
               })

      for geometry <- ["400>x400", ">", "700w", "700>>"] do
        assert {:error, error} = Size.normalize_sizes(%{"hero" => %{"size" => geometry}})
        assert error =~ ~s(has an invalid "size" #{inspect(geometry)})
      end
    end

    test "resolves presets, with extra sizes merged on top" do
      assert {:ok, standard} = Size.normalize_sizes(:standard)
      assert standard == ImageConfig.default_config().sizes
      assert Map.keys(standard) == ~w(large medium micro small thumb xlarge)

      assert {:ok, sizes} =
               Size.normalize_sizes({:standard, %{"thumb" => %{"size" => "300x300"}, hero: %{size: "2400"}}})

      assert sizes["hero"] == %{"size" => "2400"}
      assert sizes["thumb"] == %{"size" => "300x300"}
      assert sizes["xlarge"] == standard["xlarge"]

      assert {:error, ":sizes uses the unknown size preset :huge, expected one of [:standard]"} =
               Size.normalize_sizes(:huge)
    end
  end

  test "dimensions/1 reads a geometry the way processing does" do
    assert {:ok, {700, nil}} = Size.dimensions("700")
    assert {:ok, {nil, 400}} = Size.dimensions("x400")
    assert {:ok, {400, 400}} = Size.dimensions("400x400>")
    # Past any flag, so a geometry from before they were checked still reads.
    assert {:ok, {2100, 1400}} = Size.dimensions("^2100x1400")
    assert :error = Size.dimensions("400x400x2")
  end

  describe "ImageConfig.fingerprint/1" do
    test "depends on sizes and formats, not on their order or other settings" do
      config = %ImageConfig{ImageConfig.default_config() | formats: [:jpg, :webp]}
      fingerprint = ImageConfig.fingerprint(config)

      assert fingerprint =~ ~r/^[0-9a-f]{12}$/
      assert ImageConfig.fingerprint(%{config | formats: [:webp, :jpg]}) == fingerprint
      assert ImageConfig.fingerprint(%{config | upload_path: "images/other", srcset: nil}) == fingerprint

      reordered = config.sizes |> Enum.reverse() |> Map.new()
      assert ImageConfig.fingerprint(%{config | sizes: reordered}) == fingerprint

      refute ImageConfig.fingerprint(%{config | formats: [:jpg]}) == fingerprint
      refute ImageConfig.fingerprint(put_in(config.sizes["small"]["quality"], 80)) == fingerprint
    end
  end
end

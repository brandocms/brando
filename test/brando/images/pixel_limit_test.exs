defmodule Brando.Images.PixelLimitTest do
  @moduledoc """
  A raster image is refused on its header before anything decodes it at its
  declared size (audit F27). The fixture `declared_10_gigapixels.png` is an
  83-byte PNG whose header declares 100,000 × 100,000 pixels; decoding it
  would take about 90 GB.
  """
  use ExUnit.Case, async: false

  import Brando.Test.Support, only: [put_test_env: 2]
  import ExUnit.CaptureLog

  alias Brando.Images.PixelLimit
  alias Brando.Images.Processor.Vix, as: VixProcessor

  @fixtures Path.expand("../../fixtures", __DIR__)
  @huge Path.join(@fixtures, "declared_10_gigapixels.png")
  @sample Path.join(@fixtures, "sample.jpg")

  defp put_max_pixels(max_pixels) do
    original = Application.get_env(:brando, Brando.Images, [])
    put_test_env(Brando.Images, Keyword.put(original, :max_pixels, max_pixels))
  end

  setup do
    tmp_dir = Path.join(System.tmp_dir!(), "brando_pixel_limit_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    {:ok, tmp_dir: tmp_dir}
  end

  describe "check/1" do
    test "refuses an image whose header declares more than the default 100 megapixels" do
      assert PixelLimit.max_pixels() == 100_000_000
      assert {:error, :too_many_pixels} = PixelLimit.check(@huge)
      assert :ok = PixelLimit.check(@sample)
    end

    test "follows the configured limit" do
      {:ok, img} = Image.open(@sample)
      pixels = Image.width(img) * Image.height(img)

      put_max_pixels(pixels)
      assert :ok = PixelLimit.check(@sample)

      put_max_pixels(pixels - 1)
      assert {:error, :too_many_pixels} = PixelLimit.check(@sample)
      assert PixelLimit.error_message() =~ "megapixels"
    end

    test "counts every page of an animated image, however it was opened", %{tmp_dir: tmp_dir} do
      # Distinct frames: the GIF writer folds identical ones together
      {:ok, white} = Image.new(20, 10, color: :white)
      {:ok, black} = Image.new(20, 10, color: :black)
      {:ok, strip} = Image.join([white, black, white], across: 1)
      path = Path.join(tmp_dir, "three.gif")
      {:ok, strip} = Vix.Vips.Image.mutate(strip, &Vix.Vips.MutableImage.set(&1, "page-height", :gint, 10))
      Image.write!(strip, path)

      {:ok, first_page} = Image.open(path)
      {:ok, all_pages} = Image.open(path, pages: :all)

      assert Image.pages(first_page) == 3
      assert PixelLimit.pixels(first_page) == 600
      assert PixelLimit.pixels(all_pages) == 600

      put_max_pixels(599)
      assert {:error, :too_many_pixels} = PixelLimit.check(first_page)
    end
  end

  describe "the Vix processor" do
    test "writes no size for an image over the limit", %{tmp_dir: tmp_dir} do
      dest = Path.join(tmp_dir, "small.jpg")

      params = %Brando.Images.ConversionParameters{
        image_id: 1,
        size_key: "small",
        crop: false,
        quality: "75",
        format: "jpg",
        image_src_path: @huge,
        image_dest_path: dest,
        image_dest_rel_path: "images/test/small/huge.jpg",
        resize_values: %{width: 100}
      }

      log = capture_log(fn -> VixProcessor.process_image(params) end)

      assert log =~ "too_many_pixels"
      refute File.exists?(dest)

      cropped = %{
        params
        | crop: true,
          crop_values: %{left: 0, top: 0, width: 50, height: 50},
          resize_values: %{width: 50, height: 50}
      }

      log = capture_log(fn -> VixProcessor.process_image(cropped) end)
      assert log =~ "too_many_pixels"
      refute File.exists?(dest)
    end

    test "reads the dominant colour from a thumbnail, and none for an image over the limit" do
      dir = Path.join(Brando.Tenant.Storage.current_media_root(), "images/pixel-limit")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf(dir) end)
      File.cp!(@sample, Path.join(dir, "sample.jpg"))
      File.cp!(@huge, Path.join(dir, "huge.png"))

      assert "#" <> hex = VixProcessor.get_dominant_color("images/pixel-limit/sample.jpg")
      assert String.length(hex) == 6
      assert VixProcessor.get_dominant_color("images/pixel-limit/huge.png") == nil
    end
  end

  describe "uploading" do
    setup do
      on_exit(fn -> File.rm_rf(Path.join(Brando.Tenant.Storage.current_media_root(), "images/pixel-limit")) end)
    end

    test "refuses an image over the limit before creating it, and removes the stored copy", %{tmp_dir: tmp_dir} do
      upload_path = Path.join(tmp_dir, "upload.png")
      File.cp!(@huge, upload_path)

      cfg =
        struct(Brando.Type.ImageConfig, %{
          upload_path: "images/pixel-limit",
          allowed_mimetypes: ["image/png"],
          random_filename: false
        })

      meta = %{path: upload_path, config_target: "default"}
      entry = %{client_name: "huge.png", client_type: "image/png", client_size: File.stat!(@huge).size}

      capture_log(fn ->
        assert {:error, message} = Brando.Uploads.store_upload(meta, entry, cfg, :system)
        assert message == PixelLimit.error_message()
      end)

      stored = Path.join([Brando.Tenant.Storage.current_media_root(), "images/pixel-limit", "huge.png"])
      refute File.exists?(stored)
    end
  end
end

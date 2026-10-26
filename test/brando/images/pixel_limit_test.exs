defmodule Brando.Images.PixelLimitTest do
  @moduledoc """
  A raster image is refused on its header before anything decodes it at its
  declared size (audit F27). The fixture `declared_10_gigapixels.png` is an
  83-byte PNG whose header declares 100,000 × 100,000 pixels; decoding it
  would take about 90 GB.
  """
  use ExUnit.Case, async: false
  use Brando.ConnCase

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

    test "counts every frame of a GIF, which processing decodes whole", %{tmp_dir: tmp_dir} do
      # Distinct frames: the GIF writer folds identical ones together
      {:ok, white} = Image.new(20, 10, color: :white)
      {:ok, black} = Image.new(20, 10, color: :black)
      {:ok, strip} = Image.join([white, black, white], across: 1)
      path = Path.join(tmp_dir, "three.gif")
      {:ok, strip} = Vix.Vips.Image.mutate(strip, &Vix.Vips.MutableImage.set(&1, "page-height", :gint, 10))
      Image.write!(strip, path)

      {:ok, first_page} = Image.open(path)
      {:ok, all_pages} = Image.open(path, pages: :all)

      assert PixelLimit.pixels(first_page) == 200
      assert PixelLimit.pixels(all_pages) == 600
      assert PixelLimit.open_options(path) == [pages: :all]
      assert PixelLimit.open_options("image/gif") == [pages: :all]
      assert PixelLimit.open_options("photo.webp") == []

      put_max_pixels(599)
      assert {:error, :too_many_pixels} = PixelLimit.check(path, PixelLimit.open_options(path))
      assert :ok = PixelLimit.check(path)
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

      log = capture_log(fn -> assert {:error, :too_many_pixels} = VixProcessor.process_image(params) end)

      assert log =~ "over the pixel limit"
      refute File.exists?(dest)

      cropped = %{
        params
        | crop: true,
          crop_values: %{left: 0, top: 0, width: 50, height: 50},
          resize_values: %{width: 50, height: 50}
      }

      log = capture_log(fn -> assert {:error, :too_many_pixels} = VixProcessor.process_image(cropped) end)
      assert log =~ "over the pixel limit"
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

    test "an upload over the limit leaves the original it would overwrite alone", %{tmp_dir: tmp_dir} do
      upload_path = Path.join(tmp_dir, "upload.png")
      File.cp!(@huge, upload_path)

      dir = Path.join(Brando.Tenant.Storage.current_media_root(), "images/pixel-limit")
      File.mkdir_p!(dir)
      File.cp!(@sample, Path.join(dir, "cover.jpg"))

      cfg =
        struct(Brando.Type.ImageConfig, %{
          upload_path: "images/pixel-limit",
          allowed_mimetypes: ["image/png"],
          force_filename: "cover.jpg",
          overwrite: true
        })

      meta = %{path: upload_path, config_target: "default"}
      entry = %{client_name: "huge.png", client_type: "image/png", client_size: File.stat!(@huge).size}

      capture_log(fn ->
        assert {:error, message} = Brando.Uploads.store_upload(meta, entry, cfg, :system)
        assert message == PixelLimit.error_message()
      end)

      assert File.read!(Path.join(dir, "cover.jpg")) == File.read!(@sample)
    end
  end

  describe "processing a stored image" do
    setup do
      dir = Path.join(Brando.Tenant.Storage.current_media_root(), "images/pixel-limit")
      File.mkdir_p!(Path.join(dir, "small"))
      File.cp!(@huge, Path.join(dir, "huge.png"))
      File.write!(Path.join(dir, "small/huge.png"), "a size made earlier")
      on_exit(fn -> File.rm_rf(dir) end)

      image =
        Brando.Factory.insert(:image, %{
          path: "images/pixel-limit/huge.png",
          formats: [:png],
          sizes: %{"small" => "images/pixel-limit/small/huge.png"},
          status: :processed
        })

      {:ok, image: image, size: Path.join(dir, "small/huge.png")}
    end

    test "is refused before the sizes it has are removed", %{image: image, size: size} do
      args = %{
        "image_id" => image.id,
        "config_target" => "default",
        "user_id" => nil,
        "field_full_path" => []
      }

      assert {:cancel, :too_many_pixels} = perform_job(Brando.Worker.ImageProcessor, args)
      assert File.exists?(size)
      assert Brando.Repo.get!(Brando.Images.Image, image.id).sizes == image.sizes
    end

    test "is not written over an original by the image editor's crop", %{image: image} do
      sample = Path.join(Brando.Tenant.Storage.current_media_root(), "images/pixel-limit/sample.jpg")
      File.cp!(@sample, sample)
      image = Brando.Repo.update!(Ecto.Changeset.change(image, path: "images/pixel-limit/sample.jpg"))

      assert {:error, :too_many_pixels} =
               Brando.Images.Crop.save_replace(image, File.read!(@huge), %{x: 50, y: 50}, :system)

      assert File.read!(sample) == File.read!(@sample)

      assert {:error, :too_many_pixels} =
               Brando.Images.Crop.save_as_new_copy(image, File.read!(@huge), %{x: 50, y: 50}, :system)
    end

    test "is skipped by a bulk recreate, which keeps its sizes", %{image: image, size: size} do
      Brando.Repo.update_all(Brando.Images.Image, set: [config_target: "default"])

      assert {:ok, ids} = Brando.Images.Processing.recreate_sizes_for_image_field("default", :system)
      refute image.id in ids
      assert File.exists?(size)
    end
  end
end

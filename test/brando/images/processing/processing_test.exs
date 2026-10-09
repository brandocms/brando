defmodule Brando.Images.ProcessingTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Images.Processing

  @cfg %Brando.Type.ImageConfig{
    allowed_mimetypes: ["image/jpeg", "image/png"],
    default_size: "medium",
    upload_path: Path.join("images", "avatars"),
    random_filename: false,
    size_limit: 10_240_000,
    sizes: %{
      "thumb" => %{"size" => "150x150", "quality" => 100, "crop" => true},
      "large" => %{"size" => "700", "quality" => 100}
    }
  }

  @meta %{
    path: Path.expand("../../../", __DIR__) <> "/fixtures/sample.png",
    config_target: "image:Brando.Users.User:avatar"
  }

  @upload_entry %Phoenix.LiveView.UploadEntry{
    cancelled?: false,
    client_last_modified: nil,
    client_name: "sample.png",
    client_size: 251_094,
    client_type: "image/png",
    done?: true,
    preflighted?: true,
    progress: 100,
    ref: "0",
    upload_config: :cover,
    upload_ref: "phx-FphlQp2qJhgx2QsB",
    uuid: "f4dd9ef5-1c0d-4b29-87b8-643d7144e86d",
    valid?: true
  }

  describe "a photo stored on its side" do
    # 1200×900 as stored, with EXIF orientation 6: shown as 900×1200.
    setup do
      images_config = Application.get_env(:brando, Brando.Images, [])
      put_test_env(Brando.Images, Keyword.put(images_config, :processor_module, Brando.Images.Processor.Vix))

      path = "images/sideways/#{System.unique_integer([:positive])}.jpg"
      file = Brando.Images.Utils.media_path(path)
      File.mkdir_p!(Path.dirname(file))
      on_exit(fn -> File.rm_rf!(Path.dirname(file)) end)

      {:ok, img} = Vix.Vips.Image.mutate(Image.new!(1200, 900), &Vix.Vips.MutableImage.set(&1, "orientation", :gint, 6))
      Image.write!(img, file)

      {:ok, path: path}
    end

    test "is recorded upright on upload", %{path: path} do
      user = Factory.insert(:random_user)
      upload = %{meta: %{media_path: path, config_target: "default"}, upload_entry: nil, cfg: @cfg}

      assert {:ok, image} = Brando.Uploads.Store.handle_upload_type(upload, user)
      assert {image.width, image.height} == {900, 1200}
    end

    test "recorded as stored before, it is turned upright when processed", %{path: path} do
      image = Factory.insert(:image, path: path, width: 1200, height: 900, sizes: %{})

      {:ok, _job} = Processing.queue_processing(image, :system)
      image = Brando.Repo.get!(Brando.Images.Image, image.id)
      assert {image.width, image.height} == {900, 1200}
    end
  end

  test "slugifies the client filename by default" do
    u1 = Factory.insert(:random_user)
    upload_entry = %{@upload_entry | client_name: "NTECH 12, Keynote.png"}

    {:ok, uploaded_image} = Brando.Uploads.Store.handle_upload(@meta, upload_entry, @cfg, u1)

    assert Path.basename(uploaded_image.path) =~ "ntech-12-keynote"
    refute uploaded_image.path =~ " "
    refute uploaded_image.path =~ ","
  end

  test "keeps the client filename verbatim when slugify_filename is false" do
    u1 = Factory.insert(:random_user)
    cfg = %{@cfg | slugify_filename: false}
    upload_entry = %{@upload_entry | client_name: "NTECH 12 Keynote.png"}

    {:ok, uploaded_image} = Brando.Uploads.Store.handle_upload(@meta, upload_entry, cfg, u1)

    assert uploaded_image.path =~ "NTECH 12 Keynote"
  end

  test "recreate_sizes_for_image_field" do
    u1 = Factory.insert(:random_user)

    {:ok, uploaded_image} = Brando.Uploads.Store.handle_upload(@meta, @upload_entry, @cfg, u1)
    {:ok, updated_ids} = Processing.recreate_sizes_for_image_field(Brando.Users.User, :avatar, u1)

    assert uploaded_image.id in updated_ids
    assert Enum.count(updated_ids) == 2
  end
end

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

  test "slugifies the client filename by default" do
    u1 = Factory.insert(:random_user)
    upload_entry = %{@upload_entry | client_name: "NTECH 12, Keynote.png"}

    {:ok, uploaded_image} = Brando.Upload.handle_upload(@meta, upload_entry, @cfg, u1)

    assert Path.basename(uploaded_image.path) =~ "ntech-12-keynote"
    refute uploaded_image.path =~ " "
    refute uploaded_image.path =~ ","
  end

  test "keeps the client filename verbatim when slugify_filename is false" do
    u1 = Factory.insert(:random_user)
    cfg = %{@cfg | slugify_filename: false}
    upload_entry = %{@upload_entry | client_name: "NTECH 12 Keynote.png"}

    {:ok, uploaded_image} = Brando.Upload.handle_upload(@meta, upload_entry, cfg, u1)

    assert uploaded_image.path =~ "NTECH 12 Keynote"
  end

  test "recreate_sizes_for_image_field" do
    u1 = Factory.insert(:random_user)

    {:ok, uploaded_image} = Brando.Upload.handle_upload(@meta, @upload_entry, @cfg, u1)
    {:ok, updated_ids} = Processing.recreate_sizes_for_image_field(Brando.Users.User, :avatar, u1)

    assert uploaded_image.id in updated_ids
    assert Enum.count(updated_ids) == 2
  end
end

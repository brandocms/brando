defmodule Brando.Images.ProcessingTest do
  use ExUnit.Case
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
    path: Path.expand("../../../", __DIR__) <> "/fixtures/sample.png"
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

  test "create_image_type_struct" do
    {:ok, image_struct} = Brando.Upload.handle_upload(@meta, @upload_entry, @cfg)

    assert image_struct.focal == %Brando.Images.Focal{x: 50, y: 50}
    assert image_struct.path =~ "images/avatars/sample"

    assert image_struct.height == 576
    assert image_struct.width == 608
  end

  test "recreate_sizes_for_image_field" do
    {:ok, image_struct} = Brando.Upload.handle_upload(@meta, @upload_entry, @cfg)

    u1 = Factory.insert(:random_user, avatar: image_struct)

    [{:ok, result}] = Processing.recreate_sizes_for_image_field(Brando.Users.User, :avatar, u1)
    assert result.id == u1.id
  end

  test "recreate_sizes_for_image_field_record" do
    {:ok, image_struct} = Brando.Upload.handle_upload(@meta, @upload_entry, @cfg)

    u1 = Factory.insert(:random_user, avatar: image_struct)
    changeset = Ecto.Changeset.change(u1)

    {:ok, changeset} = Processing.recreate_sizes_for_image_field_record(changeset, :avatar, u1)
    assert changeset.valid?
    assert Map.has_key?(changeset.changes, :avatar)
  end
end

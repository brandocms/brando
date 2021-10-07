defmodule Brando.Images.SharpTest do
  use ExUnit.Case
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Images.Processing
  alias Brando.Images.Processor.Sharp

  @cfg %Brando.Type.ImageConfig{
    allowed_mimetypes: ["image/jpeg", "image/png"],
    default_size: "medium",
    upload_path: Path.join("images", "avatars"),
    random_filename: true,
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

  test "handle_upload_type" do
    prev_cfg = Brando.config(Brando.Images)
    new_cfg = Keyword.put(prev_cfg, :processor_module, Brando.Images.Processor.Sharp)
    Application.put_env(:brando, Brando.Images, new_cfg)

    {:ok, image_struct} = Brando.Upload.handle_upload(@meta, @upload_entry, @cfg)

    assert image_struct.focal == %Brando.Images.Focal{x: 50, y: 50}
    assert image_struct.height == 576
    assert image_struct.width == 608
    assert image_struct.path =~ "images/avatars/"

    Application.put_env(:brando, Brando.Images, prev_cfg)
  end

  test "recreate_sizes_for_image_field" do
    prev_cfg = Brando.config(Brando.Images)
    new_cfg = Keyword.put(prev_cfg, :processor_module, Brando.Images.Processor.Sharp)
    Application.put_env(:brando, Brando.Images, new_cfg)

    {:ok, image_struct} = Brando.Upload.handle_upload(@meta, @upload_entry, @cfg)

    u1 = Factory.insert(:random_user, avatar: image_struct)

    [{:ok, result}] = Processing.recreate_sizes_for_image_field(Brando.Users.User, :avatar, u1)
    assert result.id == u1.id
    Application.put_env(:brando, Brando.Images, prev_cfg)
  end

  test "recreate_sizes_for_image_field_record" do
    prev_cfg = Brando.config(Brando.Images)
    new_cfg = Keyword.put(prev_cfg, :processor_module, Brando.Images.Processor.Sharp)
    Application.put_env(:brando, Brando.Images, new_cfg)

    {:ok, image_struct} = Brando.Upload.handle_upload(@meta, @upload_entry, @cfg)

    u1 = Factory.insert(:random_user, avatar: image_struct)
    changeset = Ecto.Changeset.change(u1)

    {:ok, changeset} = Processing.recreate_sizes_for_image_field_record(changeset, :avatar, u1)
    assert changeset.valid?
    assert Map.has_key?(changeset.changes, :avatar)
    Application.put_env(:brando, Brando.Images, prev_cfg)
  end

  test "cee" do
    assert Sharp.confirm_executable_exists() == {:ok, {:executable, :exists}}
  end
end

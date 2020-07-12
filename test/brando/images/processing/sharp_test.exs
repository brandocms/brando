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

  @up %Plug.Upload{
    content_type: "image/png",
    filename: "sample.png",
    path: Path.expand("../../../", __DIR__) <> "/fixtures/sample.png"
  }

  test "create_image_type_struct" do
    previous_module = Brando.config(Brando.Images)[:processor_module]
    Application.put_env(:brando, Brando.Images, processor_module: Brando.Images.Processor.Sharp)

    u1 = Factory.insert(:random_user)
    {:ok, upload} = Brando.Upload.process_upload(@up, @cfg)

    {:ok, image_struct} = Processing.create_image_type_struct(upload, u1)

    assert image_struct == %Brando.Type.Image{
             alt: nil,
             credits: nil,
             focal: %{x: 50, y: 50},
             height: 576,
             path: Path.join(upload.cfg.upload_path, upload.plug.filename),
             sizes: %{},
             title: nil,
             width: 608
           }

    Application.put_env(:brando, Brando.Images, processor_module: previous_module)
  end

  test "recreate_sizes_for_image_field" do
    previous_module = Brando.config(Brando.Images)[:processor_module]
    Application.put_env(:brando, Brando.Images, processor_module: Brando.Images.Processor.Sharp)

    {:ok, upload} = Brando.Upload.process_upload(@up, @cfg)
    {:ok, image_struct} = Processing.create_image_type_struct(upload, :system)
    u1 = Factory.insert(:random_user, avatar: image_struct)

    [{:ok, result}] = Processing.recreate_sizes_for_image_field(Brando.Users.User, :avatar, u1)
    assert result.id == u1.id
    Application.put_env(:brando, Brando.Images, processor_module: previous_module)
  end

  test "recreate_sizes_for_image_field_record" do
    previous_module = Brando.config(Brando.Images)[:processor_module]
    Application.put_env(:brando, Brando.Images, processor_module: Brando.Images.Processor.Sharp)

    {:ok, upload} = Brando.Upload.process_upload(@up, @cfg)
    {:ok, image_struct} = Processing.create_image_type_struct(upload, :system)
    u1 = Factory.insert(:random_user, avatar: image_struct)
    changeset = Ecto.Changeset.change(u1)

    {:ok, changeset} = Processing.recreate_sizes_for_image_field_record(changeset, :avatar, u1)
    assert changeset.valid?
    assert Map.has_key?(changeset.changes, :avatar)
    Application.put_env(:brando, Brando.Images, processor_module: previous_module)
  end

  test "cee" do
    assert Sharp.confirm_executable_exists() == {:ok, {:executable, :exists}}
  end
end

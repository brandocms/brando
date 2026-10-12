defmodule Brando.Images.ForConfigTargetTest do
  # An image picked for a field whose image config it was not made for is
  # used as a copy made for that config, so the field renders sizes it has.
  use Brando.ConnCase, async: false

  alias Brando.Factory
  alias Brando.Images
  alias Brando.Images.Image

  @meta_target "image:Brando.Pages.Page:meta_image"

  setup do
    name = "for-config-#{System.unique_integer([:positive])}.png"
    path = Path.join(["images", "articles", name])
    file = Images.Utils.media_path(path)
    File.mkdir_p!(Path.dirname(file))
    File.cp!(Path.expand("../../fixtures/sample.png", __DIR__), file)

    on_exit(fn ->
      File.rm(file)

      ["images", "meta", Path.rootname(name) <> "*"]
      |> Path.join()
      |> Images.Utils.media_path()
      |> Path.wildcard()
      |> Enum.each(&File.rm/1)
    end)

    image =
      Factory.insert(:image,
        path: path,
        config_target: "default",
        content_hash: "hash-#{name}",
        status: :processed,
        title: %{"en" => "Harbour"},
        alt: %{"en" => "A harbour at dusk"},
        focal: %Brando.Images.Focal{x: 20, y: 70}
      )

    {:ok, image: image, user: Factory.insert(:random_user)}
  end

  test "an image made for the config is used as it is", %{image: image, user: user} do
    assert {:ok, ^image} = Images.for_config_target(image, "default", user)
    refute_enqueued(worker: Brando.Worker.ImageProcessor)
  end

  test "an image made for another config is copied into the config's upload path and processed",
       %{image: image, user: user} do
    assert {:ok, %Image{} = copy} =
             Oban.Testing.with_testing_mode(:manual, fn -> Images.for_config_target(image, @meta_target, user) end)

    assert copy.id != image.id
    assert copy.config_target == @meta_target
    assert copy.status == :unprocessed
    assert copy.sizes == %{}
    assert Path.dirname(copy.path) == "images/meta"
    assert File.read!(Images.Utils.media_path(copy.path)) == File.read!(Images.Utils.media_path(image.path))
    assert copy.content_hash == image.content_hash
    assert {copy.title, copy.alt} == {image.title, image.alt}
    assert {copy.focal.x, copy.focal.y} == {20, 70}

    assert_enqueued(worker: Brando.Worker.ImageProcessor, args: %{image_id: copy.id, config_target: @meta_target})

    # The picked image is left as it was
    assert Brando.Repo.get!(Image, image.id).config_target == "default"
  end

  test "picking the same file again reuses the copy made for the config", %{image: image, user: user} do
    {:ok, copy} = Oban.Testing.with_testing_mode(:manual, fn -> Images.for_config_target(image, @meta_target, user) end)
    assert {:ok, %Image{id: id}} = Images.for_config_target(image, @meta_target, user)
    assert id == copy.id
  end

  test "an image whose file is missing is not copied", %{image: image, user: user} do
    File.rm!(Images.Utils.media_path(image.path))
    count = Brando.Repo.aggregate(Image, :count)
    assert {:error, :enoent} = Images.for_config_target(image, @meta_target, user)
    assert Brando.Repo.aggregate(Image, :count) == count
  end

  describe "find_duplicate/1" do
    test "only offers an image of the same file made for the upload's config" do
      _other_config = Factory.insert(:image, content_hash: "same", config_target: "default")
      same_config = Factory.insert(:image, content_hash: "same", config_target: @meta_target)
      upload = Factory.insert(:image, content_hash: "same", config_target: @meta_target)

      assert Images.find_duplicate(upload).id == same_config.id
      assert Images.find_duplicate(Factory.insert(:image, content_hash: "same", config_target: "gallery:x:y")) == nil
    end
  end
end

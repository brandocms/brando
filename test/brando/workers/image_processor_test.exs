defmodule Brando.Worker.ImageProcessorTest do
  # The type of an image's original comes from its path's extension. One with
  # none (an image stored before slugging kept the extension) cannot be
  # processed, and a retry would read the same path.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import ExUnit.CaptureLog

  alias Brando.Images.Image
  alias Brando.Tenant.Storage

  @sample Path.expand("../../fixtures/sample.jpg", __DIR__)

  setup do
    dir = Path.join(Storage.current_media_root(), "images/no-type")
    File.mkdir_p!(Path.join(dir, "small"))
    on_exit(fn -> File.rm_rf(dir) end)

    File.cp!(@sample, Path.join(dir, ".jpg"))
    # A size `delete_sized_images/1` reaches: the size's path in each format
    File.write!(Path.join(dir, "small/x.jpg"), "a size made earlier")

    image =
      Brando.Factory.insert(:image, %{
        path: "images/no-type/.jpg",
        formats: [:jpg],
        sizes: %{"small" => "images/no-type/small/x.jpg"},
        status: :processed
      })

    {:ok, image: image, size: Path.join(dir, "small/x.jpg")}
  end

  test "an image whose path has no image type is cancelled, keeping its sizes", %{image: image, size: size} do
    Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:image:#{image.id}")
    args = %{"image_id" => image.id, "config_target" => "default", "user_id" => nil, "field_full_path" => []}

    log =
      capture_log(fn ->
        assert {:cancel, {:unsupported_image_type, ""}} = perform_job(Brando.Worker.ImageProcessor, args)
      end)

    assert log =~ "has no image type"
    assert_receive {%Image{id: id}, [:image, :error], []} when id == image.id
    assert File.exists?(size)
    assert Brando.Repo.get!(Image, image.id).sizes == image.sizes
  end

  # On a node that has not loaded the schema yet, as an interactive release
  # just after it starts, the path's field names have no atoms. The worker
  # only passes the path on; the form converts it.
  test "a field path naming no atom on this node is passed on as stored", %{image: image} do
    Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:image:#{image.id}")
    field = "no_atom_has_this_name_#{System.unique_integer([:positive])}"
    path = ["items", 0, field]
    args = %{"image_id" => image.id, "config_target" => "default", "user_id" => nil, "field_full_path" => path}

    capture_log(fn ->
      assert {:cancel, {:unsupported_image_type, ""}} = perform_job(Brando.Worker.ImageProcessor, args)
    end)

    assert_receive {%Image{id: id}, [:image, :error], ^path} when id == image.id
  end

  test "a bulk recreate skips it and keeps its sizes", %{image: image, size: size} do
    Brando.Repo.update_all(Image, set: [config_target: "default"])

    capture_log(fn ->
      assert {:ok, ids} = Brando.Images.Processing.recreate_sizes_for_image_field("default", :system)
      refute image.id in ids
    end)

    assert File.exists?(size)
  end
end

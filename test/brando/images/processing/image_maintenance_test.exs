defmodule Brando.Images.ImageMaintenanceTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Factory
  alias Brando.ImageFileFixtures
  alias Brando.Images.Image
  alias Brando.Images.Processing
  alias Brando.Worker

  defmodule ColorProcessor do
    @moduledoc false
    def get_dominant_color("image/unreadable.jpg"), do: nil
    def get_dominant_color(_path), do: "#123456"
    defdelegate process_image(conversion_parameters), to: Brando.Images.Processor.Vix
  end

  setup do
    images_config = Application.get_env(:brando, Brando.Images, [])
    put_test_env(Brando.Images, Keyword.put(images_config, :processor_module, ColorProcessor))

    {:ok, user: Factory.insert(:random_user)}
  end

  test "recreating sizes walks every configured image in batches", %{user: user} do
    images = for n <- 1..5, do: Factory.insert(:image, path: "image/#{n}.jpg")
    deleted = Factory.insert(:image, deleted_at: DateTime.utc_now())
    # The column defaults to "default", so nil has to be written explicitly.
    unconfigured = Factory.insert(:image)
    Repo.update_all(from(i in Image, where: i.id == ^unconfigured.id), set: [config_target: nil])

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, _} =
               %{task: "recreate_sizes", user_id: user.id, batch_size: 2}
               |> Worker.ImageMaintenance.new()
               |> Oban.insert()

      # Other fixtures (the user's avatar) may add images; expect all of them.
      expected =
        Repo.all(from i in Image, where: is_nil(i.deleted_at) and not is_nil(i.config_target), select: i.id)

      batches = div(length(expected), 2) + 1
      assert %{success: ^batches, failure: 0} = Oban.drain_queue(queue: :default, with_recursion: true)

      queued_ids = Enum.map(all_enqueued(worker: Worker.ImageProcessor), & &1.args["image_id"])

      assert Enum.sort(queued_ids) == Enum.sort(expected)
      assert Enum.all?(images, &(&1.id in queued_ids))
      refute deleted.id in queued_ids
      refute unconfigured.id in queued_ids
    end)
  end

  test "recreating changed sizes queues only images made with another config", %{user: user} do
    current = Processing.current_fingerprint("default")
    assert is_binary(current)

    # Fixtures (the user's avatar) may add images; mark them all as current.
    for target <- Repo.all(from i in Image, where: not is_nil(i.config_target), distinct: true, select: i.config_target) do
      Repo.update_all(from(i in Image, where: i.config_target == ^target),
        set: [config_fingerprint: Processing.current_fingerprint(target)]
      )
    end

    unchanged = Factory.insert(:image, config_fingerprint: current)
    changed = Factory.insert(:image, config_fingerprint: "0123456789ab")
    # Processed before fingerprints were stored.
    unknown = Factory.insert(:image, config_fingerprint: nil)
    # A target that no longer resolves has nothing to recreate with.
    removed = Factory.insert(:image, config_target: "image:Brando.Pages.Page:removed_field", config_fingerprint: nil)

    assert Processing.current_fingerprint(removed.config_target) == nil
    assert Processing.count_changed_images() == 2

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, _} = Processing.recreate_sizes_for_changed_images(user)
      # Either recreate run blocks the other.
      assert {:error, :already_running} = Processing.recreate_sizes_for_images(user)

      Oban.drain_queue(queue: :default, with_recursion: true)

      queued_ids = Enum.map(all_enqueued(worker: Worker.ImageProcessor), & &1.args["image_id"])
      assert Enum.sort(queued_ids) == Enum.sort([changed.id, unknown.id])
      refute unchanged.id in queued_ids
      refute removed.id in queued_ids
    end)
  end

  test "recreating changed sizes adopts unrecorded images that match and recreates the rest", %{user: user} do
    current = Processing.current_fingerprint("default")

    for target <- Repo.all(from i in Image, where: not is_nil(i.config_target), distinct: true, select: i.config_target) do
      Repo.update_all(from(i in Image, where: i.config_target == ^target),
        set: [config_fingerprint: Processing.current_fingerprint(target)]
      )
    end

    matching = ImageFileFixtures.unrecorded_image("job-match")

    differing =
      ImageFileFixtures.unrecorded_image("job-differ", sizes: Map.delete(ImageFileFixtures.standard_sizes(), "xlarge"))

    changed = Factory.insert(:image, config_fingerprint: "0123456789ab")

    Phoenix.PubSub.subscribe(Brando.pubsub(), Processing.topic())

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, _} =
               %{task: "recreate_changed_sizes", user_id: user.id, batch_size: 2}
               |> Worker.ImageMaintenance.new()
               |> Oban.insert()

      Oban.drain_queue(queue: :default, with_recursion: true)

      queued_ids = Enum.map(all_enqueued(worker: Worker.ImageProcessor), & &1.args["image_id"])
      assert Enum.sort(queued_ids) == Enum.sort([differing.id, changed.id])
    end)

    assert Repo.get!(Image, matching.id).config_fingerprint == current
    assert Repo.get!(Image, differing.id).config_fingerprint == nil

    # The counts add up over the batches.
    assert_received {:image_maintenance, %{task: "recreate_changed_sizes", state: :running}}
    assert_received {:image_maintenance, %{task: "recreate_changed_sizes", state: :done, adopted: 1, recreated: 2}}
  end

  test "processing stores the fingerprint of the config it used", %{user: user} do
    # A fixture original test_helper copies into the media path.
    image = Factory.insert(:image, path: "images/avatars/27i97a.jpeg", config_fingerprint: nil, status: :unprocessed)

    # Oban runs inline here, so this processes the image.
    assert {:ok, _job} = Processing.queue_processing(image, user)

    image = Repo.get!(Image, image.id)
    assert image.status == :processed
    assert image.config_fingerprint == Processing.current_fingerprint("default")
    refute Processing.changed_config?(image, Processing.current_fingerprint("default"))
  end

  test "recalculating colors updates readable images and keeps the rest", %{user: user} do
    readable = Factory.insert(:image, path: "image/readable.jpg", dominant_color: nil)
    unreadable = Factory.insert(:image, path: "image/unreadable.jpg", dominant_color: "#abcdef")

    assert {:ok, _job} = Processing.set_dominant_color_for_images(user)

    assert Repo.get!(Image, readable.id).dominant_color == "#123456"
    # No color could be read, so the stored one is not overwritten with nil.
    assert Repo.get!(Image, unreadable.id).dominant_color == "#abcdef"
  end

  test "a task cannot be started twice while it is unfinished", %{user: user} do
    Oban.Testing.with_testing_mode(:manual, fn ->
      refute Processing.image_maintenance_running?("recreate_sizes")
      assert {:ok, _job} = Processing.recreate_sizes_for_images(user)
      assert Processing.image_maintenance_running?("recreate_sizes")
      assert {:error, :already_running} = Processing.recreate_sizes_for_images(user)

      # The other task is tracked separately.
      refute Processing.image_maintenance_running?("dominant_colors")
      assert {:ok, _job} = Processing.set_dominant_color_for_images(user)
    end)
  end
end

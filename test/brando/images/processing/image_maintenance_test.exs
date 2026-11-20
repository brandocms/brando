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

    # The counts add up over the batches. `:done` is the end of the walk:
    # the images are only queued.
    assert_received {:image_maintenance, %{task: "recreate_changed_sizes", state: :running}}
    assert_received {:image_maintenance, %{task: "recreate_changed_sizes", state: :done, adopted: 1, queued: 2}}
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

  # The admin who started a batch may be demoted, or gone, before it reaches
  # the last image. The batches are the system's work, as an image's sizes
  # are (`Brando.Worker.ImageProcessor`); the progress stays the admin's.
  describe "after the admin who started it is demoted or gone" do
    setup %{user: user} do
      Repo.update_all(from(u in Brando.Users.User, where: u.id == ^user.id), set: [role: :admin])
      :ok
    end

    defp demote(user), do: Repo.update_all(from(u in Brando.Users.User, where: u.id == ^user.id), set: [role: :user])
    defp delete(user), do: Repo.delete_all(from(u in Brando.Users.User, where: u.id == ^user.id))

    test "recalculating colors still stores them for a demoted admin", %{user: user} do
      image = Factory.insert(:image, path: "image/demoted.jpg", dominant_color: nil)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _job} = Processing.set_dominant_color_for_images(user)
        demote(user)
        assert %{failure: 0} = Oban.drain_queue(queue: :default, with_recursion: true)
      end)

      assert Repo.get!(Image, image.id).dominant_color == "#123456"
    end

    test "recalculating colors still stores them when the admin is gone", %{user: user} do
      image = Factory.insert(:image, path: "image/gone.jpg", dominant_color: nil)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _job} = Processing.set_dominant_color_for_images(user)
        delete(user)
        assert %{failure: 0} = Oban.drain_queue(queue: :default, with_recursion: true)
      end)

      assert Repo.get!(Image, image.id).dominant_color == "#123456"
    end

    test "recreating sizes still queues every image when the admin is gone", %{user: user} do
      image = Factory.insert(:image, path: "image/gone-sizes.jpg")

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _job} = Processing.recreate_sizes_for_images(user)
        delete(user)
        assert %{failure: 0} = Oban.drain_queue(queue: :default, with_recursion: true)

        assert image.id in Enum.map(all_enqueued(worker: Worker.ImageProcessor), & &1.args["image_id"])
      end)
    end

    # Each image's completed callback and CDN copy are still the admin's
    test "recreating sizes for a demoted admin still queues each image for them", %{user: user} do
      image = Factory.insert(:image, path: "image/demoted-sizes.jpg")
      user_id = user.id

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _job} = Processing.recreate_sizes_for_images(user)
        demote(user)
        assert %{failure: 0} = Oban.drain_queue(queue: :default, with_recursion: true)

        assert [%{args: %{"user_id" => ^user_id}}] =
                 Enum.filter(all_enqueued(worker: Worker.ImageProcessor), &(&1.args["image_id"] == image.id))
      end)
    end
  end

  # The runs write as the system, so starting one needs the right to update
  # images, read afresh
  test "a user who may not update images cannot start a run", %{user: user} do
    Repo.update_all(from(u in Brando.Users.User, where: u.id == ^user.id), set: [role: :user])

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:error, :forbidden} = Processing.recreate_sizes_for_images(user)
      assert {:error, :forbidden} = Processing.recreate_sizes_for_changed_images(user)
      assert {:error, :forbidden} = Processing.set_dominant_color_for_images(user)
      assert [] = all_enqueued(worker: Worker.ImageMaintenance)
    end)
  end

  test "in groups mode, managing Utilities is not enough to start a run" do
    alias Brando.Authorization.{Catalog, Groups, Scope}

    put_test_env(:authorization_mode, :groups)
    Brando.Authorization.Boundary.put_scope(nil)
    owner = Factory.insert(:random_user, role: :superuser)
    {:ok, _} = Brando.Authorization.Migration.run()
    member = Factory.insert(:random_user, role: :user)
    scope = Scope.standalone(owner)

    {:ok, utilities} =
      Groups.create(scope, %{name: "Utilities"}, [
        Catalog.get(:access, :backend).key,
        Catalog.get(:update, :utilities).key
      ])

    {:ok, :ok} = Groups.add_member(scope, utilities.id, member.id)

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:error, :forbidden} = Processing.set_dominant_color_for_images(member)

      {:ok, media} = Groups.create(scope, %{name: "Media"}, [Catalog.get(:update, Image).key])
      {:ok, :ok} = Groups.add_member(scope, media.id, member.id)
      assert {:ok, _job} = Processing.set_dominant_color_for_images(member)
    end)
  end

  test "the system can start a run, as from a release shell" do
    image = Factory.insert(:image, path: "image/system.jpg", dominant_color: nil)

    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, _job} = Processing.recreate_sizes_for_images(:system)
      assert {:ok, _job} = Processing.set_dominant_color_for_images(:system)
      assert %{failure: 0} = Oban.drain_queue(queue: :default, with_recursion: true)

      assert [%{args: %{"user_id" => nil}}] =
               Enum.filter(all_enqueued(worker: Worker.ImageProcessor), &(&1.args["image_id"] == image.id))
    end)

    assert Repo.get!(Image, image.id).dominant_color == "#123456"
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

  # A run reports to its admin as work, counting each image as its job ends,
  # and is going on, for every admin, while any image it queued is unfinished
  describe "a run of Image sizes" do
    alias Brando.Images.SizeRun
    alias BrandoAdmin.Work

    setup %{user: user} do
      # Only this test's images: the fixtures' (the user's avatar) are not configured
      Repo.update_all(from(i in Image, where: is_nil(i.deleted_at)), set: [config_target: nil])
      Work.subscribe(user)
      :ok
    end

    defp work(user) do
      BrandoAdmin.Work.Registry.sync()
      Work.get(user, SizeRun.work_key())
    end

    defp image_jobs, do: all_enqueued(worker: Worker.ImageProcessor)

    test "counts each image when it is processed, not when it is queued, and ends after the last", %{user: user} do
      images = for _ <- 1..3, do: Factory.insert(:image, path: "images/avatars/27i97a.jpeg")

      Oban.Testing.with_testing_mode(:manual, fn ->
        # As `Processing.recreate_sizes_for_images/1` starts it, in batches of
        # two: the run is counted across them
        SizeRun.begin(user)

        assert {:ok, _} =
                 %{task: "recreate_sizes", user_id: user.id, batch_size: 2}
                 |> Worker.ImageMaintenance.new()
                 |> Oban.insert()

        assert %{success: 2, failure: 0} = Oban.drain_queue(queue: :default, with_recursion: true)
        assert Enum.sort(Enum.map(image_jobs(), & &1.args["image_id"])) == Enum.sort(Enum.map(images, & &1.id))

        # Walked and queued: nothing is recreated yet
        assert %Work{status: :running, total: 3, done: 0} = work(user)
        assert SizeRun.running?()
        assert SizeRun.remaining() == 3

        # One image at a time: hold back all but one
        [_first | later] = image_jobs()
        later_ids = Enum.map(later, & &1.id)
        in_an_hour = DateTime.add(DateTime.utc_now(), 3600)

        Repo.update_all(from(j in Oban.Job, where: j.id in ^later_ids),
          set: [state: "scheduled", scheduled_at: in_an_hour]
        )

        assert %{success: 1, failure: 0} = Oban.drain_queue(queue: :image_processing)
        assert %Work{status: :running, total: 3, done: 1} = work(user)
        assert SizeRun.running?()

        assert %{success: 2, failure: 0} = Oban.drain_queue(queue: :image_processing, with_scheduled: true)
      end)

      assert_receive {:work, "image-sizes", :finished, %Work{done: 3, failed: 0, message: "3 images recreated"}}
      refute SizeRun.running?()
    end

    test "a failed image is counted and named", %{user: user} do
      ok = Factory.insert(:image, path: "images/avatars/27i97a.jpeg")
      broken = Factory.insert(:image, path: "images/avatars/broken.unknown")

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _} = Processing.recreate_sizes_for_images(user)
        Oban.drain_queue(queue: :default, with_recursion: true)
        Oban.drain_queue(queue: :image_processing, with_scheduled: true, with_recursion: true)
        watch()
      end)

      assert_receive {:work, "image-sizes", :failed, %Work{} = work}, 1000
      assert %Work{total: 2, done: 2, failed: 1, failed_items: [broken_id]} = work
      assert broken_id == broken.id
      assert Repo.get!(Image, ok.id).status == :processed
      refute SizeRun.running?()
    end

    test "a second run does not start while the first one's images wait, whoever started it", %{user: user} do
      Factory.insert(:image, path: "images/avatars/27i97a.jpeg")
      other = Factory.insert(:random_user)

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _} = Processing.recreate_sizes_for_images(user)
        Oban.drain_queue(queue: :default, with_recursion: true)

        # The walk is done (its watcher waits with the image)
        assert [%{args: %{"watch" => true}}] = all_enqueued(worker: Worker.ImageMaintenance)
        assert SizeRun.running?()
        assert {:error, :already_running} = Processing.recreate_sizes_for_images(user)
        assert {:error, :already_running} = Processing.recreate_sizes_for_changed_images(other)

        # Retrying or being processed still counts
        Repo.update_all(from(j in Oban.Job, where: j.worker == "Brando.Worker.ImageProcessor"), set: [state: "retryable"])
        assert {:error, :already_running} = Processing.recreate_sizes_for_images(other)

        Repo.update_all(from(j in Oban.Job, where: j.worker == "Brando.Worker.ImageProcessor"),
          set: [state: "executing", attempted_at: DateTime.utc_now()]
        )

        assert {:error, :already_running} = Processing.recreate_sizes_for_images(other)

        Repo.update_all(from(j in Oban.Job, where: j.worker == "Brando.Worker.ImageProcessor"), set: [state: "completed"])
        watch()
        refute SizeRun.running?()
        assert {:ok, _} = Processing.recreate_sizes_for_images(other)
      end)
    end

    test "an image queued outside a run does not hold one", %{user: user} do
      image = Factory.insert(:image, path: "images/avatars/27i97a.jpeg")

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _} = Processing.queue_processing(image, user)
        refute SizeRun.running?()
      end)
    end

    test "a run with nothing to recreate ends at once", %{user: user} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _} = Processing.recreate_sizes_for_images(user)
        assert %Work{status: :running, total: 0} = work(user)

        Oban.drain_queue(queue: :default, with_recursion: true)
        watch()
      end)

      assert_receive {:work, "image-sizes", :finished, %Work{total: 0, done: 0, message: "No images to recreate"}}
      refute SizeRun.running?()
    end

    # The jobs are the truth: the work follows them when they are replaced,
    # retried, cancelled, or outlive the node that counted them

    defp walk_and_wait(user) do
      assert {:ok, walk} = Processing.recreate_sizes_for_images(user)
      Oban.drain_queue(queue: :default, with_recursion: true)
      walk
    end

    # The run's watcher, once its images are done, ends what is left of it
    defp watch, do: Oban.drain_queue(queue: :default, with_scheduled: true, with_recursion: true)

    test "an image saved again while its run's job waits is still counted", %{user: user} do
      images = for _ <- 1..2, do: Factory.insert(:image, path: "images/avatars/27i97a.jpeg")

      Oban.Testing.with_testing_mode(:manual, fn ->
        walk_and_wait(user)

        # The image editor saves a focal point: the waiting job is replaced
        assert {:ok, _} = Processing.queue_processing(hd(images), user, [], silent: true)
        assert SizeRun.remaining() == 2

        assert %{success: 2} = Oban.drain_queue(queue: :image_processing, with_scheduled: true)
      end)

      assert_receive {:work, "image-sizes", :finished, %Work{total: 2, done: 2, failed: 0}}
    end

    test "a run whose job is cancelled from outside ends, as failed", %{user: user} do
      for _ <- 1..2, do: Factory.insert(:image, path: "images/avatars/27i97a.jpeg")

      Oban.Testing.with_testing_mode(:manual, fn ->
        walk_and_wait(user)

        [cancelled | _] = image_jobs()
        Repo.update_all(from(j in Oban.Job, where: j.id == ^cancelled.id), set: [state: "cancelled"])
        assert %{success: 1} = Oban.drain_queue(queue: :image_processing, with_scheduled: true)

        watch()
      end)

      assert_receive {:work, "image-sizes", :failed, %Work{total: 2, done: 1}}
      refute SizeRun.running?()
    end

    test "a retried batch counts and queues its images once", %{user: user} do
      for _ <- 1..2, do: Factory.insert(:image, path: "images/avatars/27i97a.jpeg")

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, walk} = Processing.recreate_sizes_for_images(user)
        assert :ok = perform_job(Worker.ImageMaintenance, walk.args)
        first = Enum.map(image_jobs(), & &1.id)

        # The attempt queued its images and failed after: Oban runs it again
        assert :ok = perform_job(Worker.ImageMaintenance, walk.args)
        assert Enum.sort(Enum.map(image_jobs(), & &1.id)) == Enum.sort(first)
        assert %Work{total: 2} = work(user)

        assert %{success: 2} = Oban.drain_queue(queue: :image_processing, with_scheduled: true)
      end)

      assert_receive {:work, "image-sizes", :finished, %Work{total: 2, done: 2}}
    end

    test "a walk that gives up still lets its run end", %{user: user} do
      Factory.insert(:image, path: "images/avatars/27i97a.jpeg")

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, walk} = Processing.recreate_sizes_for_images(user)
        Repo.update_all(from(j in Oban.Job, where: j.id == ^walk.id), set: [state: "discarded"])

        watch()
      end)

      assert_receive {:work, "image-sizes", :failed, %Work{}}
      refute SizeRun.running?()
    end

    # The registry is in memory: a restarted node knows no run
    defp forget(user) do
      Work.fail(user, SizeRun.work_key())
      assert_receive {:work, "image-sizes", :failed, %Work{}}
    end

    test "a run's next batch after a restart reports it as it was started", %{user: user} do
      for _ <- 1..3, do: Factory.insert(:image, path: "images/avatars/27i97a.jpeg")

      Oban.Testing.with_testing_mode(:manual, fn ->
        SizeRun.begin(user)

        assert {:ok, _} =
                 %{task: "recreate_sizes", user_id: user.id, batch_size: 2}
                 |> Worker.ImageMaintenance.new()
                 |> Oban.insert()

        # The first batch
        assert %{success: 1} = Oban.drain_queue(queue: :default)
        forget(user)

        assert %{success: 1} = Oban.drain_queue(queue: :default)

        assert %Work{status: :running, total: 3, done: 0, open: false, timeout: 1_800_000} = run = work(user)
        assert run.message
        assert run.failed_message

        assert %{success: 3} = Oban.drain_queue(queue: :image_processing, with_scheduled: true)
      end)

      assert_receive {:work, "image-sizes", :finished, %Work{total: 3, done: 3}}
    end

    test "a run restarted after its walk is reported again until its images are done", %{user: user} do
      for _ <- 1..2, do: Factory.insert(:image, path: "images/avatars/27i97a.jpeg")

      Oban.Testing.with_testing_mode(:manual, fn ->
        walk_and_wait(user)
        forget(user)

        # The watcher's next look
        Oban.drain_queue(queue: :default, with_scheduled: true)
        assert %Work{status: :running, total: 2, done: 0} = work(user)

        assert %{success: 2} = Oban.drain_queue(queue: :image_processing, with_scheduled: true)
      end)

      assert_receive {:work, "image-sizes", :finished, %Work{total: 2, done: 2}}
    end

    defp watcher do
      assert [watcher] = Enum.filter(all_enqueued(worker: Worker.ImageMaintenance), & &1.args["watch"])
      watcher
    end

    defp flush_work do
      receive do
        {:work, _key, _status, _work} -> flush_work()
      after
        0 -> :ok
      end
    end

    defp set_job(job, fields), do: Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id), set: fields)

    # The watcher's look comes up to seconds after the last image: the run
    # is over when its walk and images are, and its watcher's late look
    # leaves a run started since alone
    test "a run whose images are done is over before its watcher looks", %{user: user} do
      Factory.insert(:image, path: "images/avatars/27i97a.jpeg")

      Oban.Testing.with_testing_mode(:manual, fn ->
        walk_and_wait(user)
        old_watcher = watcher()
        assert %{success: 1} = Oban.drain_queue(queue: :image_processing, with_scheduled: true)
        assert_receive {:work, "image-sizes", :finished, %Work{}}

        refute SizeRun.running?()
        assert {:ok, _} = Processing.recreate_sizes_for_images(user)
        assert %Work{status: :running} = work(user)

        assert :ok = perform_job(Worker.ImageMaintenance, Map.put(old_watcher.args, "settle", true))
        assert %Work{status: :running} = work(user)
      end)
    end

    # The watcher reads one image left; that image's report ends the work
    # before the watcher's resume reaches the registry
    test "the watcher's late resume does not bring back a run that has ended", %{user: user} do
      Factory.insert(:image, path: "images/avatars/27i97a.jpeg")

      Oban.Testing.with_testing_mode(:manual, fn ->
        walk_and_wait(user)
        [job] = image_jobs()
        watcher = watcher()

        # The watcher's read, while the job runs
        assert SizeRun.remaining() == 1
        assert %{success: 1} = Oban.drain_queue(queue: :image_processing, with_scheduled: true)
        assert_receive {:work, "image-sizes", :finished, %Work{}}

        flush_work()

        # Its resume, after the report
        set_job(job, state: "executing", attempted_at: DateTime.utc_now())
        assert {:snooze, _} = perform_job(Worker.ImageMaintenance, watcher.args)
        set_job(job, state: "completed")
        assert :ok = perform_job(Worker.ImageMaintenance, Map.put(watcher.args, "settle", true))
        BrandoAdmin.Work.Registry.sync()
      end)

      refute_received {:work, "image-sizes", _, _}
    end

    # The attempt queued its images and failed after: the images processed
    # before the retry now match their config
    test "a retried batch of changed images counts the images it queued before", %{user: user} do
      images =
        for _ <- 1..3, do: Factory.insert(:image, path: "images/avatars/27i97a.jpeg", config_fingerprint: "0123456789ab")

      Oban.Testing.with_testing_mode(:manual, fn ->
        run = SizeRun.begin(user)
        args = %{"task" => "recreate_changed_sizes", "user_id" => user.id, "batch_size" => 2, "run" => run}

        assert :ok = perform_job(Worker.ImageMaintenance, args)
        # Its next batch was never queued
        Repo.delete_all(from(j in Oban.Job, where: j.worker == "Brando.Worker.ImageMaintenance"))

        [first | later] = image_jobs()
        for job <- later, do: set_job(job, state: "scheduled", scheduled_at: DateTime.add(DateTime.utc_now(), 3600))
        assert %{success: 1} = Oban.drain_queue(queue: :image_processing)

        refute Processing.changed_config?(
                 Repo.get!(Image, first.args["image_id"]),
                 Processing.current_fingerprint("default")
               )

        assert :ok = perform_job(Worker.ImageMaintenance, args)
        assert [next] = all_enqueued(worker: Worker.ImageMaintenance)
        assert next.args["queued"] == 2
        assert :ok = perform_job(Worker.ImageMaintenance, next.args)

        queued_ids =
          Repo.all(from(j in Oban.Job, where: j.worker == "Brando.Worker.ImageProcessor", select: j.args["image_id"]))

        assert Enum.sort(queued_ids) == Enum.sort(Enum.map(images, & &1.id))
        assert %Work{total: 3, open: false, message: "Recreating image sizes"} = work(user)

        assert %{success: 2} = Oban.drain_queue(queue: :image_processing, with_scheduled: true)
      end)

      assert_receive {:work, "image-sizes", :finished, %Work{total: 3, done: 3, message: "3 images recreated"}}
    end

    test "a run restated after a restart keeps the images that failed before it", %{user: user} do
      images = for _ <- 1..2, do: Factory.insert(:image, path: "images/avatars/27i97a.jpeg")

      failed_id =
        Oban.Testing.with_testing_mode(:manual, fn ->
          walk_and_wait(user)

          [failed, _waiting] = image_jobs()
          set_job(failed, state: "discarded", discarded_at: DateTime.utc_now())
          forget(user)

          # The watcher's next look
          assert {:snooze, _} = perform_job(Worker.ImageMaintenance, watcher().args)
          failed_id = failed.args["image_id"]
          assert %Work{status: :running, total: 2, done: 1, failed: 1, failed_items: [^failed_id]} = work(user)

          assert %{success: 1} = Oban.drain_queue(queue: :image_processing, with_scheduled: true)
          failed_id
        end)

      assert_receive {:work, "image-sizes", :failed, %Work{total: 2, done: 2, failed: 1, failed_items: [^failed_id]}}
      assert failed_id in Enum.map(images, & &1.id)
    end

    test "an image job left executing past its timeout does not hold a run" do
      image = Factory.insert(:image, path: "images/avatars/27i97a.jpeg")

      job =
        %{image_id: image.id, config_target: image.config_target, user_id: nil, field_full_path: [], silent: true}
        |> Worker.ImageProcessor.new(meta: %{"image_size_run" => true})
        |> Repo.insert!()

      Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id),
        set: [state: "executing", attempted_at: DateTime.add(DateTime.utc_now(), -3600)]
      )

      refute SizeRun.running?()

      Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id), set: [attempted_at: DateTime.utc_now()])
      assert SizeRun.running?()
    end
  end
end

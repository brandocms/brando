defmodule BrandoAdmin.UtilsImageToolsLiveTest do
  use Brando.LiveCase, async: true
  use Oban.Testing, repo: BrandoIntegration.Repo

  import Ecto.Query, only: [from: 2]

  alias Brando.Factory
  alias Brando.Images.SizeRun
  alias Brando.Worker.ImageMaintenance
  alias BrandoAdmin.Work.Registry

  setup do
    put_test_env(:authorization_mode, :legacy)
    put_test_env(:tenancy_mode, :none)
  end

  # Tests run Oban inline, and the testing mode is per process: inside the
  # LiveView a queued run executes and finishes at once.
  test "running an image tool completes it in the background", %{conn: conn} do
    {:ok, view, _} = live(conn, "/admin/config/utils")

    assert has_element?(view, "h3", "Image sizes")
    assert has_element?(view, "h3", "Dominant colors")

    view |> element("button", "Recreate image sizes") |> render_click()
    view |> element("button", "Recalculate colors") |> render_click()

    refute has_element?(view, "button[phx-click=recreate_image_sizes][disabled]")
    refute has_element?(view, "small", "Running in the background")
  end

  test "recreates only the images made with older settings", %{conn: conn} do
    current = Brando.Images.Processing.current_fingerprint("default")
    # The fixture original test_helper copies into the media path.
    path = "images/avatars/27i97a.jpeg"
    Factory.insert(:image, path: path, config_fingerprint: "0123456789ab")
    Factory.insert(:image, path: path, config_fingerprint: current)

    changed = Brando.Images.Processing.count_changed_images()
    assert changed > 0

    {:ok, view, _} = live(conn, "/admin/config/utils")

    assert has_element?(view, "small", "#{changed} images were made with older settings")

    # Inline in the LiveView: the changed images are processed at once.
    view |> element("button", "Recreate changed images") |> render_click()

    assert Brando.Images.Processing.count_changed_images() == 0
    assert has_element?(view, "small", "All images match their settings")
    assert has_element?(view, "button[phx-click=recreate_changed_image_sizes][disabled]")
    refute has_element?(view, "button[phx-click=recreate_image_sizes][disabled]")
  end

  test "with no image files in the media folder, asks for the media instead of urging a recreate", %{conn: conn} do
    Brando.Repo.update_all(Brando.Images.Image, set: [deleted_at: DateTime.utc_now()])
    Factory.insert(:image, path: "images/unsynced/1.jpg", config_fingerprint: nil)
    root = Brando.Images.Utils.media_path()

    {:ok, view, _} = live(conn, "/admin/config/utils")

    assert has_element?(view, "#utils-unsynced-media", "No image files found under #{root}")
    refute has_element?(view, "button.btn--primary[phx-click=recreate_changed_image_sizes]")

    Factory.insert(:image, path: "images/avatars/27i97a.jpeg", config_fingerprint: nil)
    {:ok, view, _} = live(conn, "/admin/config/utils")

    refute has_element?(view, "#utils-unsynced-media")
    assert has_element?(view, "button.btn--primary[phx-click=recreate_changed_image_sizes]")
  end

  # The run's work reaches the view through the registry
  defp render_work(view) do
    Registry.sync()
    render(view)
  end

  test "keeps unrecorded images that already match and says how many it recreated", %{conn: conn} do
    Brando.Repo.update_all(Brando.Images.Image, set: [config_fingerprint: "0123456789ab"])
    matching = Brando.ImageFileFixtures.unrecorded_image("utils-match")
    Factory.insert(:image, path: "images/avatars/27i97a.jpeg", config_fingerprint: "0123456789ab")

    {:ok, view, _} = live(conn, "/admin/config/utils")
    refute has_element?(view, "#utils-image-run")

    view |> element("button", "Recreate changed images") |> render_click()

    assert Brando.Repo.get!(Brando.Images.Image, matching.id).config_fingerprint ==
             Brando.Images.Processing.current_fingerprint("default")

    recreated = Brando.Repo.aggregate(Brando.Images.Image, :count) - 1
    render_work(view)
    assert has_element?(view, "#utils-image-run[data-adopted=\"1\"]")
    assert has_element?(view, "#work-status-image-sizes[data-status=finished]", "#{recreated} images recreated")
    refute has_element?(view, "#utils-image-failures")
  end

  test "either recreate run blocks both buttons", %{conn: conn, current_user: user} do
    Oban.Testing.with_testing_mode(:manual, fn ->
      {:ok, _job} = Oban.insert(ImageMaintenance.new(%{task: "recreate_changed_sizes", user_id: user.id}))

      {:ok, view, _} = live(conn, "/admin/config/utils")

      assert has_element?(view, "button[phx-click=recreate_image_sizes][disabled]")
      assert has_element?(view, "button[phx-click=recreate_changed_image_sizes][disabled]")

      render_click(view, "recreate_image_sizes")
      assert [] = all_enqueued(worker: ImageMaintenance, args: %{task: "recreate_sizes"})
    end)
  end

  test "an unfinished run disables its tool and is not started again", %{conn: conn, current_user: user} do
    Oban.Testing.with_testing_mode(:manual, fn ->
      {:ok, _job} = Oban.insert(ImageMaintenance.new(%{task: "recreate_sizes", user_id: user.id}))

      {:ok, view, _} = live(conn, "/admin/config/utils")

      assert has_element?(view, "button[phx-click=recreate_image_sizes][disabled]")
      assert has_element?(view, "#utils-image-sizes-running")
      # The other tool is tracked separately.
      refute has_element?(view, "button[phx-click=recalculate_dominant_colors][disabled]")

      # A forged click while it runs does not queue a second run.
      render_click(view, "recreate_image_sizes")
      assert [_] = all_enqueued(worker: ImageMaintenance, args: %{task: "recreate_sizes"})
    end)
  end

  # The tools write as the system: a legacy User account, which edits
  # nothing, cannot start them by sending the event
  test "a legacy user demoted since the page opened cannot start an image tool", %{conn: conn, current_user: user} do
    Oban.Testing.with_testing_mode(:manual, fn ->
      Process.flag(:trap_exit, true)

      for event <- ~w(recreate_image_sizes recreate_changed_image_sizes recalculate_dominant_colors) do
        Brando.Users.User |> Brando.Repo.get!(user.id) |> Ecto.Changeset.change(role: :superuser) |> Brando.Repo.update!()
        {:ok, view, _} = live(conn, "/admin/config/utils")
        Brando.Users.User |> Brando.Repo.get!(user.id) |> Ecto.Changeset.change(role: :user) |> Brando.Repo.update!()

        # The view ends, for the client to rejoin at the stored role
        catch_exit(render_click(view, event, %{}))
      end

      assert [] = all_enqueued(worker: ImageMaintenance)

      # The context refuses the user the view held, too
      assert {:error, :forbidden} = Brando.Images.Processing.recreate_sizes_for_images(user)
    end)
  end

  describe "a run of Image sizes" do
    setup do
      # Only this test's images
      Brando.Repo.update_all(Brando.Images.Image, set: [config_target: nil])
      :ok
    end

    test "shows the run's count, and names the images it could not recreate", %{conn: conn} do
      Factory.insert(:image, path: "images/avatars/27i97a.jpeg")
      broken = Factory.insert(:image, path: "images/avatars/broken.unknown")

      {:ok, view, _} = live(conn, "/admin/config/utils")
      view |> element("button[phx-click=recreate_image_sizes]") |> render_click()
      render_work(view)

      assert has_element?(view, "#work-status-image-sizes[data-status=failed]")
      assert has_element?(view, "#utils-image-failures[data-count=\"1\"]")

      assert has_element?(
               view,
               ~s(#utils-image-failures a[data-image-id="#{broken.id}"][href="/admin/assets/images/update/#{broken.id}"]),
               "broken.unknown"
             )

      refute has_element?(view, "button[phx-click=recreate_image_sizes][disabled]")
    end

    test "a run with nothing to recreate says so at once", %{conn: conn} do
      {:ok, view, _} = live(conn, "/admin/config/utils")
      view |> element("button[phx-click=recreate_image_sizes]") |> render_click()
      render_work(view)

      assert has_element?(view, "#work-status-image-sizes[data-status=finished]")
      refute has_element?(view, "button[phx-click=recreate_image_sizes][disabled]")
    end

    # Another admin's run, opened or reloaded while its images wait: the
    # page has no work of its own for it, and asks the jobs
    test "images another admin's run queued keep both buttons disabled until they are done", %{conn: conn} do
      other = Factory.insert(:random_user)
      image = Factory.insert(:image, path: "images/avatars/27i97a.jpeg")

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert SizeRun.queue([image], other) == 1
        assert [job] = all_enqueued(worker: Brando.Worker.ImageProcessor)

        {:ok, view, _} = live(conn, "/admin/config/utils")

        assert has_element?(view, "button[phx-click=recreate_image_sizes][disabled]")
        assert has_element?(view, "button[phx-click=recreate_changed_image_sizes][disabled]")
        assert has_element?(view, "#utils-image-sizes-running[data-remaining=\"1\"]")
        refute has_element?(view, "#work-status-image-sizes[data-status]")

        # A forged click queues nothing
        render_click(view, "recreate_image_sizes")
        render_click(view, "recreate_changed_image_sizes")
        assert [] = all_enqueued(worker: ImageMaintenance)

        # Still waiting at the next check
        send(view.pid, :check_image_tasks)
        assert has_element?(view, "button[phx-click=recreate_image_sizes][disabled]")

        Brando.Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id), set: [state: "completed"])
        send(view.pid, :check_image_tasks)

        refute has_element?(view, "button[phx-click=recreate_image_sizes][disabled]")
        refute has_element?(view, "#utils-image-sizes-running")
      end)
    end

    # Pages already open hear that a run started, whoever started it
    test "a run another admin starts disables both buttons on a page already open", %{conn: conn} do
      other = Factory.insert(:random_user, role: :admin)
      Factory.insert(:image, path: "images/avatars/27i97a.jpeg")

      {:ok, view, _} = live(conn, "/admin/config/utils")
      refute has_element?(view, "button[phx-click=recreate_image_sizes][disabled]")

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, _} = Brando.Images.Processing.recreate_sizes_for_images(other)

        assert has_element?(view, "button[phx-click=recreate_image_sizes][disabled]")
        assert has_element?(view, "button[phx-click=recreate_changed_image_sizes][disabled]")
      end)
    end

    test "the failure count keeps up past the images it names", %{conn: conn, current_user: user} do
      {:ok, view, _} = live(conn, "/admin/config/utils")

      work = %BrandoAdmin.Work{
        id: SizeRun.work_key(),
        key: SizeRun.work_key(),
        user_id: user.id,
        total: 300,
        done: 100,
        failed: 100,
        failed_items: Enum.to_list(1..100)
      }

      send(view.pid, {:work, SizeRun.work_key(), :running, work})
      assert has_element?(view, "#utils-image-failures[data-count=\"100\"]")

      send(view.pid, {:work, SizeRun.work_key(), :running, %{work | done: 250, failed: 250}})
      assert has_element?(view, "#utils-image-failures[data-count=\"250\"]")
    end
  end
end

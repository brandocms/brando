defmodule BrandoAdmin.UtilsImageToolsLiveTest do
  use Brando.LiveCase
  use Oban.Testing, repo: BrandoIntegration.Repo

  alias Brando.Factory
  alias Brando.Worker.ImageMaintenance

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
    assert has_element?(view, "#utils-image-run", "1 image already matched its settings")
    assert has_element?(view, "#utils-image-run", "#{recreated} images recreated")
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
      assert has_element?(view, "small", "Running in the background")
      # The other tool is tracked separately.
      refute has_element?(view, "button[phx-click=recalculate_dominant_colors][disabled]")

      # A forged click while it runs does not queue a second run.
      render_click(view, "recreate_image_sizes")
      assert [_] = all_enqueued(worker: ImageMaintenance, args: %{task: "recreate_sizes"})
    end)
  end
end

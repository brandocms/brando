defmodule BrandoAdmin.UtilsImageToolsLiveTest do
  use Brando.LiveCase
  use Oban.Testing, repo: BrandoIntegration.Repo

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

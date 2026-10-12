defmodule Mix.Tasks.Brando.Images.AdoptTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Ecto.Query, only: [from: 2]

  alias Brando.ImageFileFixtures
  alias Brando.Images.Image
  alias Brando.Images.Processing
  alias Mix.Tasks.Brando.Images.Adopt

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

    # Fixtures (the user's avatar) may add images; keep them out of the counts.
    Repo.update_all(from(i in Image, where: is_nil(i.config_fingerprint)), set: [config_fingerprint: "fixture"])
    :ok
  end

  defp output do
    receive do
      {:mix_shell, :info, [text]} -> [text | output()]
    after
      0 -> []
    end
  end

  test "adopts the images that match and names the rest" do
    matching = ImageFileFixtures.unrecorded_image("task-match")
    differing = ImageFileFixtures.unrecorded_image("task-differ", formats: [:jpg, :webp])

    Adopt.run([])

    assert [line, hint] = output()
    assert line == "1 adopted, 1 differ, 0 skipped"
    assert hint =~ "Recreate the 1 that differ with Utilities → Recreate changed images"

    assert Repo.get!(Image, matching.id).config_fingerprint == Processing.current_fingerprint("default")
    assert Repo.get!(Image, differing.id).config_fingerprint == nil

    # Again: nothing more to adopt.
    Adopt.run([])
    assert ["0 adopted, 1 differ, 0 skipped" | _hint] = output()
  end

  test "--dry-run counts and writes nothing" do
    matching = ImageFileFixtures.unrecorded_image("task-dry")

    Adopt.run(["--dry-run"])

    assert ["1 already match, 0 differ, 0 skipped", "\nRun without --dry-run to record them."] = output()
    assert Repo.get!(Image, matching.id).config_fingerprint == nil
  end

  test "--verbose says what differs, then counts by config target and reason" do
    sizes = ImageFileFixtures.standard_sizes()
    keys = ImageFileFixtures.unrecorded_image("task-keys", sizes: %{"small" => {700, 525}, "hero" => {2400, 1800}})
    formats = ImageFileFixtures.unrecorded_image("task-formats", formats: [:jpg, :webp])
    small = ImageFileFixtures.unrecorded_image("task-small", sizes: %{sizes | "large" => {1200, 800}})
    other = ImageFileFixtures.unrecorded_image("task-small-2", sizes: %{sizes | "large" => {1000, 700}})

    Adopt.run(["--verbose"])
    lines = output()

    assert "  image #{keys.id} (default): sizes: missing [\"large\", \"medium\", \"micro\", \"thumb\", \"xlarge\"], extra [\"hero\"]" in lines

    assert "  image #{formats.id} (default): formats: has [:jpg, :webp], config [:jpg]" in lines
    assert "  image #{small.id} (default): large: 1200×800 vs config 800×600" in lines
    assert "  image #{other.id} (default): large: 1000×700 vs config 800×600" in lines

    assert List.last(lines) =~ "Recreate the 4 that differ"

    assert Enum.at(lines, -2) ==
             Enum.join(
               [
                 "\nBy config target and reason:",
                 "  2 × (default): large: other dimensions",
                 "  1 × (default): formats: has [:jpg, :webp], config [:jpg]",
                 "  1 × (default): sizes: missing [\"large\", \"medium\", \"micro\", \"thumb\", \"xlarge\"], extra [\"hero\"]"
               ],
               "\n"
             )
  end

  test "--yes is accepted and an unknown option stops the task" do
    Adopt.run(["--yes", "--dry-run"])
    assert ["0 already match, 0 differ, 0 skipped"] = output()

    assert_raise Mix.Error, ~r/mix brando.images.adopt: unknown or invalid option --all/, fn -> Adopt.run(["--all"]) end
  end

  describe "tenancy" do
    @prefix "tenant_adopttask_preview"

    setup do
      put_test_env(:tenancy_mode, :multi)
      Brando.Tenant.put_prefix(nil)

      {:ok, site} =
        Brando.Tenant.Registry.create_site(%{
          name: "Adopt task",
          key: "adopttask",
          languages: ["en"],
          default_language: "en",
          status: :active,
          delivery_mode: :dynamic
        })

      {:ok, _environment} =
        Brando.Tenant.Registry.create_environment(site, %{name: "Preview", key: "preview", live: true})

      Repo.query!(~s(CREATE SCHEMA "#{@prefix}"))
      Repo.query!(~s|CREATE TABLE "#{@prefix}"."images" (LIKE public."images" INCLUDING ALL)|)
      on_exit(fn -> Brando.Tenant.put_prefix(nil) end)
      :ok
    end

    test "goes through every environment of every active site" do
      image = Brando.Tenant.with_prefix(@prefix, fn -> ImageFileFixtures.unrecorded_image("task-tenant") end)

      Adopt.run([])

      assert "[adopttask/preview] 1 adopted, 0 differ, 0 skipped" in output()
      assert Brando.Tenant.with_prefix(@prefix, fn -> Brando.Repo.get!(Image, image.id).config_fingerprint end)
    end
  end
end

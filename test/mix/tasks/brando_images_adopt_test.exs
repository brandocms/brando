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

  test "--verbose says why an image differs" do
    differing = ImageFileFixtures.unrecorded_image("task-verbose", sizes: %{"small" => {700, 525}})

    Adopt.run(["--verbose"])

    assert "  image #{differing.id} (default): its sizes differ" in output()
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

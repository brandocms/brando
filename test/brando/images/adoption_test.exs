defmodule Brando.Images.AdoptionTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Factory
  alias Brando.ImageFileFixtures
  alias Brando.Images.Adoption
  alias Brando.Images.Image
  alias Brando.Images.Processing

  @sizes ImageFileFixtures.standard_sizes()

  setup do
    # Fixtures (the user's avatar) may add images; keep them out of the counts.
    Repo.update_all(from(i in Image, where: is_nil(i.config_fingerprint)), set: [config_fingerprint: "fixture"])
    :ok
  end

  describe "adopt_unrecorded/1" do
    test "adopts an image whose formats, sizes and files match, and changes nothing else" do
      image = Repo.get!(Image, unrecorded("match").id)
      fingerprint = Processing.current_fingerprint("default")

      assert Processing.adopt_unrecorded() == %{adopted: 1, differ: 0, skipped: 0}

      adopted = Repo.get!(Image, image.id)
      assert adopted.config_fingerprint == fingerprint
      assert Map.delete(adopted, :config_fingerprint) == Map.delete(image, :config_fingerprint)

      # Nothing left to do the second time.
      assert Processing.adopt_unrecorded() == %{adopted: 0, differ: 0, skipped: 0}
    end

    test "a dry run counts and writes nothing" do
      image = unrecorded("dry")

      assert Processing.adopt_unrecorded(dry_run: true) == %{adopted: 1, differ: 0, skipped: 0}
      assert Repo.get!(Image, image.id).config_fingerprint == nil
    end

    test "a missing or extra size, other formats, other dimensions or a missing file differ" do
      missing_key = unrecorded("missing-key", sizes: Map.delete(@sizes, "xlarge"))
      extra_key = unrecorded("extra-key", sizes: Map.put(@sizes, "hero", {2400, 1800}))
      formats = unrecorded("formats", formats: [:jpg, :webp])
      dimensions = unrecorded("dimensions", sizes: %{@sizes | "small" => {640, 480}})
      cropped = unrecorded("cropped", sizes: %{@sizes | "thumb" => {400, 300}})
      missing_file = unrecorded("missing-file")
      File.rm!(media("images/adoption/medium/missing-file.jpg"))

      differing = [missing_key, extra_key, formats, dimensions, cropped, missing_file]
      reasons = collect_differ(fn on_differ -> Processing.adopt_unrecorded(on_differ: on_differ) end)

      assert %{adopted: 0, differ: 6, skipped: 0} = reasons.counts

      assert reasons.verdicts == %{
               missing_key.id => {:differ, :size_keys},
               extra_key.id => {:differ, :size_keys},
               formats.id => {:differ, :formats},
               dimensions.id => {:differ, {:dimensions, "small"}},
               cropped.id => {:differ, {:dimensions, "thumb"}},
               missing_file.id => {:differ, {:missing, "medium"}}
             }

      for image <- differing, do: assert(Repo.get!(Image, image.id).config_fingerprint == nil)
    end

    test "without stored dimensions, the original's are read; without an original it differs" do
      measured = unrecorded("measured")
      write("images/adoption/measured.jpg", {800, 600})
      unmeasured = unrecorded("unmeasured")

      Repo.update_all(from(i in Image, where: i.id in ^[measured.id, unmeasured.id]), set: [width: nil, height: nil])

      reasons = collect_differ(fn on_differ -> Processing.adopt_unrecorded(on_differ: on_differ) end)

      assert reasons.counts == %{adopted: 1, differ: 1, skipped: 0}
      assert reasons.verdicts == %{unmeasured.id => {:differ, {:dimensions, "large"}}}
      assert Repo.get!(Image, measured.id).config_fingerprint
    end

    test "every format's file has to exist" do
      config = config()
      image = unrecorded("two-formats", formats: [:jpg, :webp], write: [:jpg])

      assert Adoption.check(image, %{config | formats: [:jpg, :webp]}) == {:differ, {:missing, "large"}}

      for {key, dimensions} <- @sizes, do: write("images/adoption/#{key}/two-formats.webp", dimensions)
      assert Adoption.check(image, %{config | formats: [:jpg, :webp]}) == :match
    end

    test "the files processing makes today match" do
      images_config = Application.get_env(:brando, Brando.Images, [])
      put_test_env(Brando.Images, Keyword.put(images_config, :processor_module, Brando.Images.Processor.Vix))

      # A fixture original test_helper copies into the media path; Oban runs
      # inline here, so this processes it.
      square = Factory.insert(:image, path: "images/avatars/27i97a.jpeg", width: 300, height: 292, sizes: %{})
      # And a portrait original, larger than some sizes.
      write("images/adoption/portrait.jpg", {900, 1350})
      portrait = Factory.insert(:image, path: "images/adoption/portrait.jpg", width: 900, height: 1350, sizes: %{})

      for image <- [square, portrait] do
        {:ok, _job} = Processing.queue_processing(image, :system)
        assert map_size(Repo.get!(Image, image.id).sizes) == 6
      end

      Repo.update_all(from(i in Image, where: i.id in ^[square.id, portrait.id]), set: [config_fingerprint: nil])

      assert Processing.adopt_unrecorded() == %{adopted: 2, differ: 0, skipped: 0}
    end

    test "files from the older processor match: fit to the width, never enlarged" do
      # A portrait 900×1200 original. libvips fits "700" into 700×700; sharp
      # made it 700 wide and kept the original's size where it was smaller.
      sharp = %{
        "micro" => {25, 33},
        "thumb" => {400, 400},
        "small" => {700, 933},
        "medium" => {900, 1200},
        "large" => {900, 1200},
        "xlarge" => {900, 1200}
      }

      image = unrecorded("sharp", original: {900, 1200}, sizes: sharp)
      assert Adoption.check(image, config()) == :match
    end

    test "files processing makes now match: widths kept, nothing enlarged" do
      # A portrait is as wide as its size, and a 300×200 original is never
      # enlarged: its square thumb is the largest square it holds.
      portrait = %{
        "micro" => {25, 33},
        "thumb" => {400, 400},
        "small" => {700, 933},
        "medium" => {900, 1200},
        "large" => {900, 1200},
        "xlarge" => {900, 1200}
      }

      small = %{
        "micro" => {25, 17},
        "thumb" => {200, 200},
        "small" => {300, 200},
        "medium" => {300, 200},
        "large" => {300, 200},
        "xlarge" => {300, 200}
      }

      assert Adoption.check(unrecorded("now-portrait", original: {900, 1200}, sizes: portrait), config()) == :match
      assert Adoption.check(unrecorded("now-small", original: {300, 200}, sizes: small), config()) == :match
    end

    test "files from the first libvips processor match: a width fitted in a square, enlarged" do
      portrait = %{
        "micro" => {19, 25},
        "thumb" => {400, 400},
        "small" => {525, 700},
        "medium" => {825, 1100},
        "large" => {1275, 1700},
        "xlarge" => {1575, 2100}
      }

      small = %{
        "micro" => {25, 17},
        "thumb" => {400, 400},
        "small" => {700, 467},
        "medium" => {1100, 733},
        "large" => {1700, 1133},
        "xlarge" => {2100, 1400}
      }

      assert Adoption.check(unrecorded("vix-portrait", original: {900, 1200}, sizes: portrait), config()) == :match
      assert Adoption.check(unrecorded("vix-small", original: {300, 200}, sizes: small), config()) == :match
    end

    test "an original rotated by its EXIF orientation matches" do
      # Stored as 800×600, the dimensions before rotation, and processed
      # upright, as 600×800.
      rotated = Map.new(@sizes, fn {key, {width, height}} -> {key, {height, width}} end)
      image = unrecorded("rotated", sizes: rotated)
      assert Adoption.check(image, config()) == :match
    end

    test "records only: formats and size keys, without reading files" do
      image = unrecorded("records", write: [])

      assert Adoption.check(image, config(), check: :records) == :match
      assert Adoption.check(image, config()) == {:differ, {:missing, "large"}}
    end

    test "images already fingerprinted are left alone" do
      recorded = unrecorded("recorded")
      Repo.update_all(from(i in Image, where: i.id == ^recorded.id), set: [config_fingerprint: "0123456789ab"])

      assert Processing.adopt_unrecorded() == %{adopted: 0, differ: 0, skipped: 0}
      assert Repo.get!(Image, recorded.id).config_fingerprint == "0123456789ab"
    end

    test "images on the CDN without local files, or without a config, are skipped" do
      cdn = unrecorded("cdn", write: [])
      Repo.update_all(from(i in Image, where: i.id == ^cdn.id), set: [cdn: true])
      removed = unrecorded("removed", config_target: "image:Brando.Pages.Page:removed_field")

      reasons = collect_differ(fn on_differ -> Processing.adopt_unrecorded(on_differ: on_differ) end)

      assert reasons.counts == %{adopted: 0, differ: 0, skipped: 2}
      assert reasons.verdicts == %{cdn.id => {:skipped, :cdn}, removed.id => {:skipped, :no_config}}
    end

    test "walks the images in batches" do
      images = for n <- 1..5, do: unrecorded("batch-#{n}")

      assert Processing.adopt_unrecorded(batch_size: 2) == %{adopted: 5, differ: 0, skipped: 0}
      assert Enum.all?(images, &Repo.get!(Image, &1.id).config_fingerprint)
    end
  end

  describe "tenancy" do
    @prefix "tenant_adoption_preview"

    setup do
      put_test_env(:tenancy_mode, :multi)
      Repo.query!(~s(CREATE SCHEMA "#{@prefix}"))
      Repo.query!(~s|CREATE TABLE "#{@prefix}"."images" (LIKE public."images" INCLUDING ALL)|)
      on_exit(fn -> Brando.Tenant.put_prefix(nil) end)
      :ok
    end

    test "adopts the images of the current environment only, from its media folder" do
      public = Brando.Tenant.with_prefix(nil, fn -> unrecorded("public", write: []) end)
      tenant = Brando.Tenant.with_prefix(@prefix, fn -> unrecorded("tenant") end)

      assert Brando.Tenant.with_prefix(@prefix, fn -> Processing.adopt_unrecorded() end) ==
               %{adopted: 1, differ: 0, skipped: 0}

      assert Brando.Tenant.with_prefix(@prefix, fn -> Brando.Repo.get!(Image, tenant.id).config_fingerprint end)
      assert Brando.Repo.get!(Image, public.id).config_fingerprint == nil
    end
  end

  defp unrecorded(name, opts \\ []), do: ImageFileFixtures.unrecorded_image(name, opts)

  defp write(path, dimensions), do: ImageFileFixtures.write_image(path, dimensions)

  defp media(path), do: Brando.Images.Utils.media_path(path)

  defp config do
    {:ok, config, _fingerprint} = Processing.current_config("default")
    config
  end

  defp collect_differ(fun) do
    parent = self()
    counts = fun.(fn image, verdict -> send(parent, {:verdict, image.id, verdict}) end)
    %{counts: counts, verdicts: receive_verdicts(%{})}
  end

  defp receive_verdicts(acc) do
    receive do
      {:verdict, id, verdict} -> receive_verdicts(Map.put(acc, id, verdict))
    after
      0 -> acc
    end
  end
end

defmodule Brando.Media.OrphanCleanupUntenantedTest do
  # An install without tenancy has one schema and one media root. The cleanup
  # reads the repo's own image and file rows; the nightly job only runs when
  # the site asks for it.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Media.OrphanCleanup
  alias Brando.Repo
  alias Brando.Worker.MediaOrphanCleanup

  setup do
    media_root =
      Path.join(System.tmp_dir!(), "brando-media-orphan-#{System.unique_integer([:positive])}")

    File.mkdir_p!(media_root)
    put_test_env(:media_path, media_root)
    on_exit(fn -> File.rm_rf!(media_root) end)

    kept =
      Factory.insert(:image,
        path: "images/site/kept.jpg",
        sizes: %{"small" => "images/site/small/kept.jpg"},
        formats: [:jpg, :webp]
      )

    trashed =
      Factory.insert(:image,
        path: "images/site/trashed.jpg",
        sizes: %{"small" => "images/site/small/trashed.jpg"},
        formats: [:jpg],
        deleted_at: DateTime.truncate(DateTime.utc_now(), :second)
      )

    Repo.insert!(%Brando.Files.File{filename: "report.pdf", config_target: "default", filesize: 1})
    {:ok, file_config} = Brando.Files.get_config_for("default")

    referenced = [
      "images/site/kept.jpg",
      "images/site/small/kept.jpg",
      "images/site/small/kept.webp",
      "images/site/trashed.jpg",
      "images/site/small/trashed.jpg",
      Path.join(file_config.upload_path, "report.pdf")
    ]

    orphans = ["files/gone.txt", "images/site/gone.jpg", "images/site/small/gone.webp"]

    Enum.each(
      referenced ++ orphans ++ ["images/site/logo.svg", "images/.gitkeep", "sitemaps/sitemap.xml"],
      &write_media!(media_root, &1)
    )

    %{media_root: media_root, kept: kept, trashed: trashed, referenced: referenced, orphans: orphans}
  end

  defp write_media!(root, relative_path) do
    path = Path.join(root, relative_path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, relative_path)
  end

  defp exists?(c, relative_path), do: File.exists?(Path.join(c.media_root, relative_path))

  test "a dry run names the files no row references and removes nothing", c do
    assert {:ok, %{dry_run: true, deleted: deleted, root: root}} =
             OrphanCleanup.run(nil, older_than_seconds: 0, dry_run: true)

    assert deleted == c.orphans
    assert root == Path.expand(c.media_root)
    assert Enum.all?(c.orphans, &exists?(c, &1))
  end

  test "removes the orphans; keeps referenced files, a trashed image's files, SVGs, dotfiles and other folders", c do
    assert {:ok, %{deleted: deleted}} = OrphanCleanup.run(nil, older_than_seconds: 0)

    assert deleted == c.orphans
    refute Enum.any?(c.orphans, &exists?(c, &1))
    assert Enum.all?(c.referenced, &exists?(c, &1))
    assert exists?(c, "images/site/logo.svg")
    assert exists?(c, "images/.gitkeep")
    assert exists?(c, "sitemaps/sitemap.xml")
  end

  test "once a trashed image's row is purged, its files are orphans", c do
    Repo.delete!(c.trashed)

    assert {:ok, %{deleted: deleted}} = OrphanCleanup.run(nil, older_than_seconds: 0)
    assert "images/site/trashed.jpg" in deleted
    assert "images/site/small/trashed.jpg" in deleted
    assert exists?(c, "images/site/kept.jpg")
  end

  test "files younger than the grace period are left alone", c do
    assert {:ok, %{deleted: []}} = OrphanCleanup.run(nil)
    assert Enum.all?(c.orphans, &exists?(c, &1))
  end

  test "with tenancy on, a run without a site is refused", c do
    put_test_env(:tenancy_mode, :single)

    assert {:error, :site_required} = OrphanCleanup.run(nil, older_than_seconds: 0)
    assert Enum.all?(c.orphans, &exists?(c, &1))
  end

  test "the nightly job does nothing unless the site asks for the cleanup", c do
    job = %Oban.Job{args: %{"older_than_seconds" => 0}}

    assert :ok = MediaOrphanCleanup.perform(job)
    assert Enum.all?(c.orphans, &exists?(c, &1))

    put_test_env(:media_orphan_cleanup, true)

    assert :ok = MediaOrphanCleanup.perform(job)
    refute Enum.any?(c.orphans, &exists?(c, &1))
    assert exists?(c, "images/site/kept.jpg")
  end
end

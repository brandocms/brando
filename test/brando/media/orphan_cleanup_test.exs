defmodule Brando.Media.OrphanCleanupTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Environments.Schema
  alias Brando.Media.OrphanCleanup
  alias Brando.Tenant
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry

  setup do
    put_test_env(:tenancy_mode, :single)
    put_test_env(:site_key, "orphan-cleanup")
    Cache.clear()

    media_root =
      Path.join(System.tmp_dir!(), "brando-media-orphan-#{System.unique_integer([:positive])}")

    File.mkdir_p!(media_root)
    put_test_env(:media_path, media_root)
    on_exit(fn -> File.rm_rf!(media_root) end)

    {:ok, site} =
      Registry.create_site(%{
        name: "Orphan cleanup",
        key: "orphan-cleanup",
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :dynamic
      })

    {:ok, production} =
      Registry.create_environment(site, %{name: "Production", key: "production", live: true})

    {:ok, preview} =
      Registry.create_environment(site, %{name: "Preview", key: "preview", live: false})

    Enum.each([production, preview], &create_asset_tables(site, &1))

    %{media_root: media_root, preview: preview, production: production, site: site}
  end

  test "deletes only files unreferenced across every environment", context do
    production_prefix = Tenant.prefix(context.site, context.production)
    preview_prefix = Tenant.prefix(context.site, context.preview)

    sql!(
      ~s|INSERT INTO "#{production_prefix}".images (path, sizes, formats) VALUES ($1, $2, $3)|,
      ["images/shared.jpg", %{"small" => "images/small/shared.jpg"}, ["jpg"]]
    )

    sql!(
      ~s|INSERT INTO "#{preview_prefix}".images (path, sizes, formats) VALUES ($1, $2, $3)|,
      ["images/preview.jpg", %{}, []]
    )

    {:ok, file_config} = Brando.Files.get_config_for("default")
    referenced_file = Path.join(file_config.upload_path, "shared.pdf")

    sql!(
      ~s|INSERT INTO "#{preview_prefix}".files (filename, config_target) VALUES ($1, $2)|,
      ["shared.pdf", "default"]
    )

    referenced = [
      "images/shared.jpg",
      "images/small/shared.jpg",
      "images/preview.jpg",
      referenced_file
    ]

    Enum.each(referenced, &write_media!(context.media_root, &1))
    write_media!(context.media_root, "images/orphan.jpg")
    write_media!(context.media_root, "files/orphan.txt")
    write_media!(context.media_root, "images/orphan.svg")

    assert {:ok, dry_run} =
             OrphanCleanup.run(context.site,
               media_root: context.media_root,
               older_than_seconds: 0,
               dry_run: true
             )

    assert dry_run.deleted == ["files/orphan.txt", "images/orphan.jpg"]
    assert File.exists?(Path.join(context.media_root, "images/orphan.jpg"))

    assert {:ok, report} =
             OrphanCleanup.run(context.site,
               media_root: context.media_root,
               older_than_seconds: 0
             )

    assert report.deleted == ["files/orphan.txt", "images/orphan.jpg"]
    Enum.each(referenced, &assert(File.exists?(Path.join(context.media_root, &1))))
    assert File.exists?(Path.join(context.media_root, "images/orphan.svg"))
    refute File.exists?(Path.join(context.media_root, "images/orphan.jpg"))
    refute File.exists?(Path.join(context.media_root, "files/orphan.txt"))
  end

  test "deletes nothing when any environment cannot be inspected", context do
    preview_prefix = Tenant.prefix(context.site, context.preview)
    sql!(~s|DROP TABLE "#{preview_prefix}".files|)
    write_media!(context.media_root, "images/orphan.jpg")

    assert {:error, {:environment_scan_failed, "preview", _reason}} =
             OrphanCleanup.run(context.site,
               media_root: context.media_root,
               older_than_seconds: 0
             )

    assert File.exists?(Path.join(context.media_root, "images/orphan.jpg"))
  end

  test "runs for one site through Oban", context do
    write_media!(context.media_root, "images/orphan.jpg")

    assert :ok =
             Brando.Worker.MediaOrphanCleanup.perform(%Oban.Job{
               args: %{"site_id" => context.site.id, "older_than_seconds" => 0}
             })

    refute File.exists?(Path.join(context.media_root, "images/orphan.jpg"))
  end

  defp create_asset_tables(site, environment) do
    prefix = Tenant.prefix(site, environment)
    assert :ok = Schema.create(prefix)

    sql!("""
    CREATE TABLE "#{prefix}".images (
      path text,
      sizes jsonb,
      formats varchar[]
    )
    """)

    sql!("""
    CREATE TABLE "#{prefix}".files (
      filename text,
      config_target text
    )
    """)
  end

  defp write_media!(root, relative_path) do
    path = Path.join(root, relative_path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, relative_path)
  end

  defp sql!(statement, params \\ []) do
    Ecto.Adapters.SQL.query!(Brando.Repo.repo(), statement, params)
  end
end

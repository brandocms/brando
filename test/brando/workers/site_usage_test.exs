defmodule Brando.Worker.SiteUsageTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import ExUnit.CaptureLog

  alias Brando.Sites.Usage
  alias Brando.Sites.Usage.Day
  alias Brando.Sites.Usage.Measure
  alias Brando.SiteAssetsFixtures
  alias Brando.SSG.Builds
  alias Brando.Tenant
  alias Brando.Tenant.Storage
  alias Brando.Worker.SiteUsage

  setup do
    root = Path.join(System.tmp_dir!(), "brando-site-usage-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "media"))
    put_test_env(:tenancy_mode, :multi)
    put_test_env(:media_path, Path.join(root, "media"))
    put_test_env(:sites_path, Path.join(root, "sites"))
    Tenant.Cache.clear()

    on_exit(fn ->
      File.chmod(root, 0o755)
      System.cmd("chmod", ["-R", "u+rwx", root])
      File.rm_rf(root)
      Tenant.Cache.clear()
    end)

    {:ok, acme} = SiteAssetsFixtures.create_site("Acme", "usage-job-acme", "acme.usage-job.test")
    {:ok, beta} = SiteAssetsFixtures.create_site("Beta", "usage-job-beta", "beta.usage-job.test")

    {:ok, _staging} =
      Tenant.Registry.create_environment(acme, %{name: "Staging", key: "staging", live: false}, actor: :system)

    %{acme: Tenant.Registry.get_site(acme.id), beta: beta, root: root}
  end

  defp write(path, bytes) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, String.duplicate("x", bytes))
  end

  defp create_schema(schema, rows) do
    Brando.Repo.repo().query!(~s(CREATE SCHEMA "#{schema}"))
    Brando.Repo.repo().query!(~s|CREATE TABLE "#{schema}".things (id bigserial PRIMARY KEY, body text)|)

    Brando.Repo.repo().query!(
      ~s|INSERT INTO "#{schema}".things (body) SELECT repeat('y', 500) FROM generate_series(1, $1)|,
      [rows]
    )

    Measure.schema_bytes(schema)
  end

  defp today, do: Date.utc_today()

  describe "measuring" do
    test "a site with two environments, one archived, its media and its kept builds", %{acme: acme, root: root} do
      production = create_schema("tenant_usage-job-acme_production", 200)
      staging = create_schema("tenant_usage-job-acme_staging", 1)
      archive = create_schema("tenant_usage-job-acme_staging_archive_20261101120000", 5)
      # Another site's schema, whose key starts with this one's
      create_schema("tenant_usage-job-acme-two_production", 1)

      write(Path.join([Storage.media_root(acme), "images", "a.jpg"]), 1_000)
      write(Path.join([Storage.media_root(acme), "b.pdf"]), 200)
      # Never followed: a link inside the folder, to a big folder elsewhere
      write(Path.join([root, "elsewhere", "big.bin"]), 50_000)
      File.ln_s!(Path.join(root, "elsewhere"), Path.join(Storage.media_root(acme), "linked"))

      # Measured although the site is dynamic today
      write(Path.join([Builds.build_root(acme), "v1", "index.html"]), 300)

      assert %{media_bytes: 1_200, builds_bytes: 300, databases: databases} = Measure.site(acme)

      assert Enum.sort_by(databases, & &1["schema"]) == [
               %{
                 "schema" => "tenant_usage-job-acme_production",
                 "environment" => "production",
                 "archive" => false,
                 "bytes" => production
               },
               %{
                 "schema" => "tenant_usage-job-acme_staging",
                 "environment" => "staging",
                 "archive" => false,
                 "bytes" => staging
               },
               %{
                 "schema" => "tenant_usage-job-acme_staging_archive_20261101120000",
                 "environment" => "staging",
                 "archive" => true,
                 "bytes" => archive
               }
             ]

      assert production > staging
    end

    test "follows a media root that is itself a link", %{acme: acme, root: root} do
      write(Path.join([root, "shared-media", "a.jpg"]), 700)
      File.mkdir_p!(Path.dirname(Storage.media_root(acme)))
      File.ln_s!(Path.join(root, "shared-media"), Storage.media_root(acme))

      assert Measure.site(acme).media_bytes == 700
    end

    test "the free space of the volume holding a path", %{root: root} do
      assert Measure.free_bytes(root) > 0
      assert Measure.free_bytes(Path.join(root, "missing")) == nil
    end

    test "a schema that does not exist has no size" do
      assert Measure.schema_bytes("tenant_usage-job-gone_production") == nil
    end
  end

  describe "the daily job" do
    test "measures every site, and one's failure stops neither the next nor the pruning", %{
      acme: acme,
      beta: beta
    } do
      old = Date.shift(today(), month: -13) |> Date.add(-1)
      kept = Date.shift(today(), month: -13)
      :ok = Usage.add_traffic([{beta.id, old, 1, 1}, {beta.id, kept, 1, 1}])
      :ok = Usage.put_measurement(acme.id, Date.add(today(), -1), %{media_bytes: 5, builds_bytes: 0, databases: []})

      unreadable = Path.join(Storage.media_root(acme), "unreadable")
      File.mkdir_p!(unreadable)
      File.chmod!(unreadable, 0o000)
      write(Path.join(Storage.media_root(beta), "a.jpg"), 40)

      log = capture_log(fn -> assert :ok = perform_job(SiteUsage, %{"all" => true}) end)
      assert log =~ "Could not measure usage-job-acme"

      # Acme keeps its last snapshot, from yesterday
      assert %{measured: %Day{media_bytes: 5}} = Usage.overview(today())[acme.id]
      assert %{measured: %Day{media_bytes: 40, day: day}} = Usage.overview(today())[beta.id]
      assert day == today()

      assert Brando.Repo.all(Day, prefix: "public")
             |> Enum.filter(&(&1.site_id == beta.id))
             |> Enum.map(& &1.day)
             |> Enum.sort(Date) == [kept, today()]
    end

    test "is unique per day, and Measure now once per waiting job", %{acme: acme} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, first} = Oban.insert(SiteUsage.new(%{"all" => true}))
        {:ok, second} = Oban.insert(SiteUsage.new(%{"all" => true}))
        assert second.conflict?
        assert second.id == first.id

        {:ok, measure} = SiteUsage.measure_now(acme)
        refute measure.conflict?
        {:ok, again} = SiteUsage.measure_now(acme)
        assert again.conflict?
      end)
    end

    test "Measure now measures one site, and announces it", %{acme: acme, beta: beta} do
      Usage.subscribe()
      write(Path.join(Storage.media_root(acme), "a.jpg"), 10)

      assert :ok = perform_job(SiteUsage, %{"site_id" => acme.id})

      assert_receive {:site_usage_measured, site_id}
      assert site_id == acme.id
      assert [%Day{media_bytes: 10}] = Usage.days(acme, today())
      assert Usage.days(beta, today()) == []

      # A site deleted since it was queued is skipped
      Brando.Repo.delete!(beta)
      assert :ok = perform_job(SiteUsage, %{"site_id" => beta.id})
    end

    test "does nothing outside :multi, also a job queued before the mode changed", %{acme: acme} do
      for mode <- [:none, :single] do
        put_test_env(:tenancy_mode, mode)
        assert :ok = perform_job(SiteUsage, %{"all" => true})
        assert :ok = perform_job(SiteUsage, %{"site_id" => acme.id})
      end

      assert Brando.Repo.all(Day, prefix: "public") == []
    end
  end
end

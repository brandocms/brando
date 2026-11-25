defmodule Brando.SSG.TargetReviewTest do
  use Brando.ConnCase

  import Brando.SSGSSHFixtures, only: [keyscan_line: 2, other_host_key: 0]

  alias Brando.Sites.DeployConfig
  alias Brando.SSG.Builds
  alias Brando.SSG.Deploy
  alias Brando.SSG.DeployFiles
  alias Brando.SSG.TargetReview
  alias Brando.Tenant.Access
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry
  alias Brando.Worker.SSGBuild
  alias Brando.Worker.SSGDeploy

  @target "deploy@example.test:/srv/www"

  defmodule Builder do
    @moduledoc false
    def build(_site, _environment, opts) do
      File.mkdir_p!(opts[:output_path])
      File.write!(Path.join(opts[:output_path], "index.html"), "built")
      {:ok, %{file_count: 1, total_size: 5, url_count: 1, processed_urls: 1, failed_urls: []}}
    end
  end

  setup do
    root = Path.join(System.tmp_dir!(), "brando-target-review-#{System.unique_integer([:positive])}")
    put_test_env(:tenancy_mode, :multi)
    put_test_env(:authorization_mode, :legacy)
    put_test_env(DeployConfig, rsync_targets: [@target, "deploy@example.test:/srv/{site_key}"])
    put_test_env(:sites_path, Path.join(root, "sites"))
    put_test_env(:media_path, Path.join(root, "media"))
    Cache.clear()

    on_exit(fn ->
      File.rm_rf(root)
      Cache.clear()
    end)

    site = site("acme")
    Brando.SSGSSHFixtures.trust_hosts(site, ["example.test"])

    %{
      site: site,
      other: site("beta"),
      environment: hd(site.environments),
      superuser: Brando.Factory.insert(:random_user, role: :superuser)
    }
  end

  defp site(name) do
    {:ok, site} =
      Registry.create_site(%{
        name: name,
        key: "#{name}-#{System.unique_integer([:positive])}",
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :static,
        deploy_config: %{strategy: :rsync, target: @target}
      })

    {:ok, _environment} =
      Registry.create_environment(site, %{name: "Production", key: "production", live: true}, actor: :system)

    Registry.get_site(site.id)
  end

  # Answers a listing with `paths` on lines of its own format, a fetch of
  # `.htaccess` with `htaccess`, and says what ran
  defp runner(paths, opts \\ []) do
    test_pid = self()

    fn "rsync", args, _opts ->
      send(test_pid, {:rsync, args})
      answer(args, paths, opts)
    end
  end

  defp answer(["-e", _ssh, "-rlp", "--max-size=" <> _ | rest], _paths, opts) do
    dir = List.last(rest)
    if text = opts[:htaccess], do: File.write!(Path.join(dir, ".htaccess"), text)
    {"", 0}
  end

  defp answer(args, paths, opts) do
    case Enum.find(args, &String.starts_with?(&1, "--out-format=")) do
      nil -> {"", 0}
      "--out-format=" <> format -> {Keyword.get(opts, :said, "") <> listed(format, paths), Keyword.get(opts, :status, 0)}
    end
  end

  defp listed(format, paths) do
    nonce = format |> String.split(" ") |> hd()
    Enum.map_join(paths, &"#{nonce} *deleting  |#{&1}\n")
  end

  defp ready_build(site, environment) do
    {:ok, build} = Builds.request_build(site, environment, [])
    {:ok, build} = Builds.update(build, %{status: :ready, built_at: DateTime.utc_now()})
    File.mkdir_p!(build.build_path)
    File.write!(Path.join(build.build_path, "index.html"), "built")
    Builds.get_build(build.id)
  end

  defp review(c, paths, opts \\ []) do
    assert {:ok, %{digest: _} = found} = TargetReview.review(c.site, c.superuser, runner: runner(paths, opts))
    found
  end

  defp state(site), do: site |> DeployFiles.read(:target_state) |> elem(1) |> :erlang.binary_to_term()

  describe "a review" do
    test "lists the target with -n, decodes names, and fetches its .htaccess", c do
      found = review(c, [".htaccess", "cgi-bin/", "cgi-bin/run", "a\\#012b", "x/"], htaccess: "Deny from all\n")

      assert found.paths == [".htaccess", "a\nb", "cgi-bin/", "cgi-bin/run", "x/"]
      assert found.htaccess == {:ok, "Deny from all\n"}

      assert_received {:rsync,
                       [
                         "-e",
                         "ssh " <> _,
                         "--timeout=300",
                         "-an",
                         "--delete",
                         "--out-format=" <> _,
                         "--",
                         _empty,
                         @target
                       ]}

      assert_received {:rsync,
                       [
                         "-e",
                         _ssh,
                         "-rlp",
                         "--max-size=32768",
                         "--info=skip1",
                         "--timeout=30",
                         "--filter=+ /.htaccess",
                         "--filter=- *",
                         "--",
                         @target <> "/",
                         _dir
                       ]}

      assert {:ok, %{reviewed: false, found: ^found, keep: [".well-known/", "cgi-bin/"]}} =
               TargetReview.status(c.site, c.superuser)
    end

    test "takes no line from the host for one of rsync's", c do
      said = "*deleting  |forged\nNOTTHENONCE *deleting  |forged\n"
      found = review(c, ["real.html"], said: said)

      assert found.paths == ["real.html"]
    end

    test "that fails or is cut short is not an empty target", c do
      assert {:error, {:rsync_failed, 23, _}} =
               TargetReview.review(c.site, c.superuser, runner: runner(["a.html"], status: 23))

      many = for n <- 1..100_001, do: "f#{n}"
      assert {:error, :listing_cut_short} = TargetReview.review(c.site, c.superuser, runner: runner(many))
      assert {:ok, %{found: nil}} = TargetReview.status(c.site, c.superuser)
    end

    test "is not made again for a reviewed target", c do
      %{digest: digest} = review(c, ["old.html"])
      assert :ok = TargetReview.confirm(c.site, c.superuser, :review, digest, [])
      assert {:ok, :reviewed} = TargetReview.review(c.site, c.superuser, runner: runner(["old.html"]))
    end

    test "is confirmed only as it was shown", c do
      %{digest: shown} = review(c, ["old.html"])
      # Another admin's test finds more
      %{digest: current} = review(c, ["old.html", "new.html"])

      assert {:error, :stale_listing} = TargetReview.confirm(c.site, c.superuser, :review, shown, [])
      assert {:error, :stale_listing} = TargetReview.confirm(c.site, c.superuser, :unknown, current, [])
      assert :ok = TargetReview.confirm(c.site, c.superuser, :review, current, ["new.html"])

      assert %{reviewed: true, confirmed: ["old.html"]} = state(c.site)
      assert "new.html" in Registry.get_site(c.site.id).deploy_config.keep_paths
    end

    test "is for the target, port and host keys it listed", c do
      %{digest: digest} = review(c, ["old.html"])
      {:ok, _site} = Registry.update_site(c.site, %{deploy_config: %{port: 2222}})

      assert {:error, :target_changed} = TargetReview.confirm(c.site, c.superuser, :review, digest, [])
    end

    test "keeps a ticked name that may not be on the keep list from being confirmed", c do
      %{digest: digest} = review(c, ["odd*name", "old.html"])
      assert :ok = TargetReview.confirm(c.site, c.superuser, :review, digest, ["odd*name"])

      assert %{confirmed: ["old.html"]} = state(c.site)
      refute "odd*name" in Registry.get_site(c.site.id).deploy_config.keep_paths
    end
  end

  describe "a deploy" do
    test "to a target not reviewed is refused on both paths, and not retried", c do
      build = ready_build(c.site, c.environment)
      put_test_env(:ssg_deploy_runner, runner([]))

      assert {:cancel, :target_not_reviewed} = perform_job(SSGDeploy, %{"build_id" => build.id, "action" => "deploy"})
      assert Builds.get_build(build.id).build_log =~ TargetReview.refusal_message(:target_not_reviewed)

      {:ok, auto} = c.site |> ready_build(c.environment) |> Builds.update(%{status: :queued, auto_deploy: true})
      put_test_env(:ssg_builder, Builder)
      assert {:error, {:deploy_failed, :target_not_reviewed}} = perform_job(SSGBuild, %{"build_id" => auto.id})

      auto = Builds.get_build(auto.id)
      assert auto.status == :ready
      assert auto.build_log =~ "Automatic deployment refused: #{TargetReview.refusal_message(:target_not_reviewed)}"
      refute_received {:rsync, _}
    end

    test "after other host keys are accepted is refused", c do
      Brando.SSGSSHFixtures.review_target(c.site, @target)
      build = ready_build(c.site, c.environment)

      # A rebuilt server's keys, accepted
      :ok = DeployFiles.write(c.site, :known_hosts, keyscan_line("example.test", other_host_key()) <> "\n")

      assert {:error, :target_not_reviewed} = Deploy.deploy(build, runner: runner([]))
      refute_received {:rsync, _}
    end

    test "of a build made for another port than the reviewed one is refused", c do
      build = ready_build(c.site, c.environment)
      Brando.SSGSSHFixtures.trust_hosts(c.site, ["example.test", "[example.test]:2222"])
      {:ok, site} = Registry.update_site(c.site, %{deploy_config: %{port: 2222}})
      Brando.SSGSSHFixtures.review_target(site, @target, 2222)

      assert {:cancel, :build_target_changed} =
               perform_job(SSGDeploy, %{"build_id" => build.id, "action" => "deploy"})

      assert Builds.get_build(build.id).build_log =~ Brando.SSG.SSH.refusal_message(:build_target_changed)
    end

    test "whose uploaded list cannot be written stops before the real run", c do
      Brando.SSGSSHFixtures.review_target(c.site, @target)
      build = ready_build(c.site, c.environment)
      state_path = DeployFiles.path(c.site, :target_state)
      listing = runner([])

      # Read before the listing; nothing can be renamed over it after
      blocking = fn "rsync", args, opts ->
        File.rm!(state_path)
        File.mkdir_p!(Path.join(state_path, "blocked"))
        listing.("rsync", args, opts)
      end

      assert {:error, {:target_state_not_written, :uploaded_list, _}} = Deploy.deploy(build, runner: blocking)

      assert_received {:rsync, args}
      assert "-an" in args
      refute_received {:rsync, _}
      assert TargetReview.refusal_message({:target_state_not_written, :uploaded_list, :eisdir}) =~ "nothing was copied"
    end

    test "keeps the build's paths as uploaded, and what else the target holds as unknown", c do
      Brando.SSGSSHFixtures.review_target(c.site, @target)
      build = ready_build(c.site, c.environment)

      assert {:ok, deployed} = Deploy.deploy(build, runner: runner(["host.html"]))
      assert %{uploaded: ["index.html"], confirmed: [], found: %{paths: ["host.html"]}} = state(c.site)
      assert deployed.build_log =~ "The target holds 1 paths Brando did not put there"
      refute DeployFiles.exists?(c.site, :filter)
    end
  end

  describe "unknown files" do
    setup c do
      Brando.SSGSSHFixtures.review_target(c.site, @target)
      first = ready_build(c.site, c.environment)
      {:ok, _deployed} = Deploy.deploy(first, runner: runner(["stray.html", "logs/", "logs/a.log"]))
      {:ok, found} = TargetReview.status(c.site, c.superuser)
      %{first: first, found: found.found}
    end

    test "are kept, or confirmed for a deploy of the deployed build when the job runs", c do
      assert :ok = TargetReview.keep(c.site, c.superuser, ["logs/"])
      assert "logs/" in Registry.get_site(c.site.id).deploy_config.keep_paths

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, job} = TargetReview.delete_unknown(c.site, c.superuser, c.found.digest, [])
        assert %{confirmed: ["stray.html"]} = state(c.site)

        # A newer build is deployed before the job runs: it stays live
        newer = ready_build(c.site, c.environment)
        assert {:ok, _deployed} = Deploy.deploy(newer, runner: runner(["stray.html"]))
        assert %{confirmed: []} = state(c.site)

        put_test_env(:ssg_deploy_runner, runner([]))
        assert :ok = perform_job(SSGDeploy, job.args)
        assert Builds.get_build(newer.id).status == :deployed
        assert Builds.get_build(c.first.id).status == :archived
      end)
    end

    test "are confirmed only as shown", c do
      assert {:error, :stale_listing} = TargetReview.delete_unknown(c.site, c.superuser, "another", [])
      assert {:error, :stale_listing} = TargetReview.confirm(c.site, c.superuser, :review, c.found.digest, [])
    end
  end

  describe "the keep list" do
    test "survives a settings save from a form read before it changed", c do
      stale = c.site
      assert :ok = TargetReview.add_keep_path(c.site, c.superuser, "uploads/")
      assert {:error, :invalid_keep_path} = TargetReview.add_keep_path(c.site, c.superuser, "../up")

      assert {:ok, saved} = Registry.update_site(stale, %{deploy_config: %{retention_count: 5}})
      assert saved.deploy_config.keep_paths == [".well-known/", "cgi-bin/", "uploads/"]

      assert :ok = TargetReview.remove_keep_path(c.site, c.superuser, "cgi-bin/")
      assert Registry.get_site(c.site.id).deploy_config.keep_paths == [".well-known/", "uploads/"]
    end

    test "and the target's files wait for a running deploy", c do
      %{digest: digest} = review(c, ["old.html"])

      lock_conn =
        start_supervised!(
          {Postgrex, Keyword.drop(Brando.Repo.repo().config(), [:pool, :ownership_pool, :pool_size, :name])}
        )

      key = Brando.Tenant.Lock.deploy_key(c.site.id)
      Postgrex.query!(lock_conn, "SELECT pg_advisory_lock(hashtextextended($1, 0))", [key])

      assert {:error, :deploy_running} = TargetReview.confirm(c.site, c.superuser, :review, digest, [])
      assert {:error, :deploy_running} = TargetReview.add_keep_path(c.site, c.superuser, "uploads/")

      Postgrex.query!(lock_conn, "SELECT pg_advisory_unlock(hashtextextended($1, 0))", [key])
      assert :ok = TargetReview.confirm(c.site, c.superuser, :review, digest, [])
    end
  end

  describe "who may act" do
    defp refused_everything(c, user) do
      assert {:error, :forbidden} = TargetReview.status(c.site, user)
      assert {:error, :forbidden} = TargetReview.review(c.site, user, runner: runner(["a"]))
      assert {:error, :forbidden} = TargetReview.confirm(c.site, user, :review, "d", [])
      assert {:error, :forbidden} = TargetReview.keep(c.site, user, ["a"])
      assert {:error, :forbidden} = TargetReview.delete_unknown(c.site, user, "d", [])
      assert {:error, :forbidden} = TargetReview.add_keep_path(c.site, user, "a")
      assert {:error, :forbidden} = TargetReview.remove_keep_path(c.site, user, ".well-known/")
      refute_received {:rsync, _}
    end

    test "with one site in legacy mode, an editor is refused", c do
      put_test_env(:tenancy_mode, :single)
      refused_everything(c, Brando.Factory.insert(:random_user, role: :editor))
    end

    test "with several sites, another site's manager is refused", c do
      manager = Brando.Factory.insert(:random_user, role: :editor)
      {:ok, _} = Access.grant(manager, c.other, :admin)
      refused_everything(c, manager)
      assert {:ok, %{reviewed: false}} = TargetReview.status(c.other, manager)
    end

    test "with capabilities, an account without publishing is refused", c do
      put_test_env(:authorization_mode, :groups)
      editor = Brando.Factory.insert(:random_user, role: :editor)
      {:ok, _} = Access.grant(editor, c.site, :editor)
      {:ok, _} = Brando.Authorization.Migration.run()
      refused_everything(c, editor)
    end
  end
end

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

  defp answer(["-e", _ssh, "-rlp", "--max-size=" <> _, _info, _timeout, _only, _rest, "--", _remote, dir], _paths, opts) do
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
                         "--max-size=262144",
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

      assert {:error, {:listing_cut_short, 100_001, 100_000} = reason} =
               TargetReview.review(c.site, c.superuser, runner: runner(many))

      assert TargetReview.refusal_message(reason) =~ "100001 paths"
      assert TargetReview.refusal_message(reason) =~ "100000"
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

    test "is confirmed only with the keep list it was shown with", c do
      %{digest: shown} = review(c, ["cgi-bin/", "cgi-bin/run", "old.html"])
      # Another admin takes cgi-bin/ off the keep list
      assert :ok = TargetReview.remove_keep_path(c.site, c.superuser, "cgi-bin/")

      assert {:error, :stale_listing} = TargetReview.confirm(c.site, c.superuser, :review, shown, [])
      assert {:ok, %{found: %{digest: current}}} = TargetReview.status(c.site, c.superuser)
      assert :ok = TargetReview.confirm(c.site, c.superuser, :review, current, ["cgi-bin/"])
      assert %{confirmed: ["old.html"]} = state(c.site)
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

    test "of a build made for the reviewed target, after the site moved to another, is refused", c do
      Brando.SSGSSHFixtures.review_target(c.site, @target)
      build = ready_build(c.site, c.environment)
      {:ok, _site} = Registry.update_site(c.site, %{deploy_config: %{target: "deploy@example.test:/srv/#{c.site.key}"}})

      assert {:error, :build_target_changed} = Deploy.deploy(build, runner: runner([]))
      refute_received {:rsync, _}
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

    test "whose filter cannot be written counts none of the build's paths as uploaded", c do
      Brando.SSGSSHFixtures.review_target(c.site, @target)
      build = ready_build(c.site, c.environment)
      listing = runner(["host.html"])

      blocking = fn "rsync", args, opts ->
        File.mkdir_p!(Path.join(DeployFiles.path(c.site, :filter), "blocked"))
        listing.("rsync", args, opts)
      end

      assert {:error, _reason} = Deploy.deploy(build, runner: blocking)
      assert %{uploaded: []} = state(c.site)
    end

    test "keeps the build's paths as uploaded, and what else the target holds as unknown", c do
      Brando.SSGSSHFixtures.review_target(c.site, @target)
      build = ready_build(c.site, c.environment)

      assert {:ok, deployed} = Deploy.deploy(build, runner: runner(["host.html"]))
      assert %{uploaded: ["index.html"], confirmed: [], found: %{paths: ["host.html"]}} = state(c.site)
      assert deployed.build_log =~ "The target holds 1 paths Brando did not put there"
      refute DeployFiles.exists?(c.site, :filter)
    end

    test "that copied, with more unknown files than are listed afterwards, does not say nothing was copied", c do
      Brando.SSGSSHFixtures.review_target(c.site, @target)
      build = ready_build(c.site, c.environment)
      listings = :counters.new(1, [])
      many = for n <- 1..100_001, do: "f#{n}"

      # The listing before the run is short; the one after it is not
      runner = fn "rsync", args, _opts ->
        if Enum.any?(args, &String.starts_with?(&1, "--out-format=")) do
          :counters.add(listings, 1, 1)
          answer(args, if(:counters.get(listings, 1) == 1, do: ["host.html"], else: many), [])
        else
          {"", 0}
        end
      end

      assert {:ok, deployed} = Deploy.deploy(build, runner: runner)
      assert :counters.get(listings, 1) == 2
      assert deployed.build_log =~ "100001"
      refute deployed.build_log =~ "nothing was copied"
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
      # The screen shows the listing again with the keep list that marks it
      assert {:ok, %{found: shown}} = TargetReview.status(c.site, c.superuser)
      refute shown.digest == c.found.digest

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, job} = TargetReview.delete_unknown(c.site, c.superuser, shown.digest, [])
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

    # The job reads the deployed build before it holds the deploy lock: a
    # deploy on another node may make another build the deployed one meanwhile
    test "are deleted by the job's deploy only while its build is still the deployed one", c do
      newer = ready_build(c.site, c.environment)
      assert {:ok, _deployed} = Deploy.deploy(newer, runner: runner([]))
      first = Builds.get_build(c.first.id)

      untouched = fn "rsync", _args, _opts -> flunk("the target was touched") end
      assert {:error, :build_no_longer_deployed} = Deploy.deploy(first, runner: untouched, only_if_deployed: true)
      assert Builds.get_build(newer.id).status == :deployed
      assert Builds.get_build(first.id).status == :archived
    end

    # Any later deploy carries a confirmation out: one left by someone who
    # may not deploy would be deployed by the next person who may
    test "are deleted only by someone who may configure and deploy, and nothing is confirmed otherwise", c do
      newer = ready_build(c.site, c.environment)
      put_test_env(:authorization_mode, :groups)
      {:ok, _} = Brando.Authorization.Migration.run()
      configurer = Brando.SSGSSHFixtures.publishing_member(c.site, c.superuser, "brando.publishing.configure")
      deployer = Brando.SSGSSHFixtures.publishing_member(c.site, c.superuser, "brando.publishing.deploy")

      Oban.Testing.with_testing_mode(:manual, fn ->
        for actor <- [configurer, deployer] do
          assert {:error, :forbidden} = TargetReview.delete_unknown(c.site, actor, c.found.digest, [])
          assert %{confirmed: []} = state(c.site)
        end

        refute_enqueued(worker: SSGDeploy)

        # The next deploy deletes nothing
        assert {:ok, _deployed} = Deploy.deploy(newer, creator: deployer, runner: runner(["stray.html"]))
        assert %{confirmed: [], uploaded: ["index.html"]} = state(c.site)

        both =
          Brando.SSGSSHFixtures.publishing_member(c.site, c.superuser, [
            "brando.publishing.configure",
            "brando.publishing.deploy"
          ])

        {:ok, %{found: found}} = TargetReview.status(c.site, both)
        assert {:ok, _job} = TargetReview.delete_unknown(c.site, both, found.digest, [])
        assert %{confirmed: ["stray.html"]} = state(c.site)
      end)
    end

    # Saved, a confirmation of unknown files is carried out by any later deploy
    test "a confirmation of unknown files is saved only for someone who may configure and deploy", c do
      put_test_env(:authorization_mode, :groups)
      {:ok, _} = Brando.Authorization.Migration.run()
      configurer = Brando.SSGSSHFixtures.publishing_member(c.site, c.superuser, "brando.publishing.configure")

      assert {:error, :forbidden} = TargetReview.confirm(c.site, configurer, :unknown, c.found.digest, [])
      assert %{confirmed: [], found: %{}} = state(c.site)
    end

    # What a deploy writes of the target's state is the deploy's own
    test "a deploy by someone who may deploy but not configure keeps the target's lists", c do
      newer = ready_build(c.site, c.environment)
      put_test_env(:authorization_mode, :groups)
      {:ok, _} = Brando.Authorization.Migration.run()
      deployer = Brando.SSGSSHFixtures.publishing_member(c.site, c.superuser, "brando.publishing.deploy")

      assert {:ok, deployed} = Deploy.deploy(newer, creator: deployer, runner: runner(["stray.html"]))
      assert deployed.status == :deployed
      assert %{reviewed: true, uploaded: ["index.html"], found: %{paths: ["stray.html"]}} = state(c.site)
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

    # A new site's Editor group may build and deploy, not configure
    test "with capabilities, an editor of the site is refused", c do
      put_test_env(:authorization_mode, :groups)
      editor = Brando.Factory.insert(:random_user, role: :editor)
      {:ok, _} = Access.grant(editor, c.site, :editor)
      {:ok, _} = Brando.Authorization.Migration.run()
      assert Builds.can_manage?(editor, c.site)
      refused_everything(c, editor)
    end

    # Building, deploying and scheduling open the Publishing screen; the
    # target's files are configuring's
    test "with capabilities, building, deploying or scheduling is refused and configuring may", c do
      put_test_env(:authorization_mode, :groups)
      {:ok, _} = Brando.Authorization.Migration.run()

      for capability <- ["brando.publishing.build", "brando.publishing.deploy", "brando.publishing.schedule"] do
        member = Brando.SSGSSHFixtures.publishing_member(c.site, c.superuser, capability)
        assert Builds.can_manage?(member, c.site)
        refused_everything(c, member)
      end

      assert {:ok, %{reviewed: false}} =
               TargetReview.status(
                 c.site,
                 Brando.SSGSSHFixtures.publishing_member(c.site, c.superuser, "brando.publishing.configure")
               )
    end
  end
end

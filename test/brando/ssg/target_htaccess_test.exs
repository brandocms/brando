defmodule Brando.SSG.TargetHtaccessTest do
  use Brando.ConnCase

  alias Brando.Sites.DeployConfig
  alias Brando.SSG.Builds
  alias Brando.SSG.Deploy
  alias Brando.SSG.DeployFiles
  alias Brando.SSG.Htaccess
  alias Brando.SSG.TargetHtaccess
  alias Brando.SSG.TargetReview
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry
  alias Brando.Worker.SSGBuild
  alias Brando.Worker.SSGDeploy

  @target "deploy@example.test:/srv/www"
  @host_lines "Options -Indexes\n"

  @redirects Jason.encode!(%{
               "version" => 1,
               "languages" => ["en"],
               "default_language" => "en",
               "redirects" => [
                 %{"source" => "/old", "pattern" => "/old$", "target" => "/new", "status" => 301, "exact" => true},
                 %{"source" => "/rel", "pattern" => "/rel$", "target" => "new", "status" => 301, "exact" => true}
               ]
             })

  @build_files [
    {"index.html", "home"},
    {"404.html", "missing"},
    {"_redirects.json", @redirects},
    {"manifest.json", ~s({"main.js": {"file": "assets/app-1a2b.js"}})},
    {"assets/app-1a2b.js", "js"}
  ]

  defmodule Builder do
    @moduledoc false
    def build(_site, _environment, opts) do
      File.mkdir_p!(opts[:output_path])
      File.write!(Path.join(opts[:output_path], "index.html"), "built")
      {:ok, %{file_count: 1, total_size: 5, url_count: 1, processed_urls: 1, failed_urls: []}}
    end
  end

  setup do
    root = Path.join(System.tmp_dir!(), "brando-target-htaccess-#{System.unique_integer([:positive])}")
    put_test_env(:tenancy_mode, :single)
    put_test_env(:authorization_mode, :legacy)
    put_test_env(DeployConfig, rsync_targets: [@target])
    put_test_env(:sites_path, Path.join(root, "sites"))
    put_test_env(:media_path, Path.join(root, "media"))
    Cache.clear()

    on_exit(fn ->
      File.rm_rf(root)
      Cache.clear()
    end)

    {:ok, site} =
      Registry.create_site(%{
        name: "Acme",
        key: "acme-#{System.unique_integer([:positive])}",
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :static,
        deploy_config: %{strategy: :rsync, target: @target, htaccess: true}
      })

    {:ok, environment} =
      Registry.create_environment(site, %{name: "Production", key: "production", live: true}, actor: :system)

    site
    |> Brando.SSGSSHFixtures.trust_hosts(["example.test"])
    |> Brando.SSGSSHFixtures.review_target(@target)

    %{site: Registry.get_site(site.id), environment: environment}
  end

  # Answers the fetch of `.htaccess` with `:htaccess` (contents, `{contents,
  # mode}`, `:link`, `:too_large` or `{:fail, status, output}`), a listing
  # with nothing, and sends the real run's arguments, rules and the merged
  # file it sends, before they are removed
  defp runner(opts \\ []) do
    test_pid = self()

    fn "rsync", args, _opts ->
      send(test_pid, {:rsync, args})

      cond do
        "-rlp" in args -> args |> fetched_into() |> fetch(Keyword.get(opts, :htaccess))
        "-az" in args -> real_run(test_pid, args)
        true -> {"", 0}
      end
    end
  end

  defp fetched_into(["-e", _ssh, "-rlp", _max, _info, _timeout, _only, _rest, "--", _remote, dir]), do: dir

  defp fetch(_dir, nil), do: {"", 0}
  defp fetch(_dir, :too_large), do: {".htaccess is over max-size\n", 0}
  defp fetch(_dir, {:fail, status, output}), do: {output, status}

  defp fetch(dir, :link) do
    File.ln_s!("/etc/hostname", Path.join(dir, ".htaccess"))
    {"", 0}
  end

  defp fetch(dir, {text, mode}) do
    path = Path.join(dir, ".htaccess")
    File.write!(path, text)
    File.chmod!(path, mode)
    {"", 0}
  end

  defp fetch(dir, text), do: fetch(dir, {text, 0o644})

  defp real_run(test_pid, args) do
    "--filter=merge " <> filter = Enum.find(args, &String.starts_with?(&1, "--filter=merge "))
    [_dash | sources] = Enum.drop_while(args, &(&1 != "--"))

    merged =
      for source <- Enum.drop(sources, -2) do
        {Path.basename(source), File.read!(source), Bitwise.band(File.stat!(source).mode, 0o777)}
      end

    send(test_pid, {:real_run, File.read!(filter), merged, Enum.take(sources, -2)})
    {"", 0}
  end

  # The first name under `tmp` that `arg` is a path in, or nil
  defp temporary_dir(arg, tmp) do
    case Path.relative_to(arg, tmp) do
      ^arg -> nil
      relative -> relative |> Path.split() |> hd()
    end
  end

  defp ready_build(c, files \\ @build_files) do
    {:ok, build} = Builds.request_build(c.site, c.environment, [])
    File.mkdir_p!(build.build_path)

    for {path, content} <- files do
      File.mkdir_p!(Path.dirname(Path.join(build.build_path, path)))
      File.write!(Path.join(build.build_path, path), content)
    end

    {:ok, build} = Builds.update(build, %{status: :ready, built_at: DateTime.utc_now()})
    Builds.get_build(build.id)
  end

  # What earlier deploys ran
  defp flush_rsync do
    receive do
      {:rsync, _args} -> flush_rsync()
    after
      0 -> :ok
    end
  end

  defp state(site), do: site |> DeployFiles.read(:target_state) |> elem(1) |> :erlang.binary_to_term()

  defp set_option(c, on?) do
    {:ok, site} = Registry.update_site(c.site, %{deploy_config: %{htaccess: on?}})
    %{c | site: site}
  end

  describe "with the option" do
    test "sends the merged .htaccess ahead of the build, protected, and hides _redirects.json", c do
      build = ready_build(c, @build_files ++ [{".htaccess", "the build's own\n"}])

      assert {:ok, deployed} = Deploy.deploy(build, runner: runner(htaccess: {@host_lines, 0o640}))

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

      assert_received {:real_run, rules, [{".htaccess", merged, 0o640}], [source, @target]}
      assert source == build.build_path <> "/"

      assert rules =~ ~r/\AP \/\.htaccess\0H \/_redirects\.json\0/
      assert String.starts_with?(merged, @host_lines <> "# BEGIN Brando\n")
      assert merged =~ "ErrorDocument 404 /404.html\n"
      assert merged =~ "RewriteRule ^ /new? [R=301,NE,L]\n"
      assert merged =~ ~s[<FilesMatch "^(?:app-1a2b\\x2ejs|app-1a2b\\x2ejs\\x2emap)$">]

      # Neither is Brando's to delete later
      assert %{block: true, uploaded: uploaded} = state(c.site)
      refute ".htaccess" in uploaded
      refute "_redirects.json" in uploaded
      assert "assets/app-1a2b.js" in uploaded

      assert deployed.build_log =~ "The build's own .htaccess was not uploaded"
      assert deployed.build_log =~ ~s[.htaccess: left out "/rel" → "new", a relative target]

      # The stored build is the same build
      assert File.read!(Path.join(build.build_path, ".htaccess")) == "the build's own\n"
      assert File.exists?(Path.join(build.build_path, "_redirects.json"))
      refute DeployFiles.exists?(c.site, :filter)
    end

    test "lists, fetches and merges in directories only this account may enter, removed after", c do
      test_pid = self()
      tmp = System.tmp_dir!()
      inner = runner(htaccess: @host_lines)

      spy = fn "rsync", args, opts ->
        for "brando-ssg" <> _rest = name <- Enum.map(args, &temporary_dir(&1, tmp)) do
          dir = Path.join(tmp, name)
          send(test_pid, {:temporary, dir, Bitwise.band(File.stat!(dir).mode, 0o777)})
        end

        inner.("rsync", args, opts)
      end

      assert {:ok, _deployed} = c |> ready_build() |> Deploy.deploy(runner: spy)

      dirs = for {:temporary, dir, mode} <- Process.info(self(), :messages) |> elem(1), do: {dir, mode}
      # The listing's, the fetch's and the merged file's
      assert length(Enum.uniq_by(dirs, &elem(&1, 0))) == 3
      assert Enum.all?(dirs, fn {_dir, mode} -> mode == 0o700 end)
      refute Enum.any?(dirs, fn {dir, _mode} -> File.exists?(dir) end)
    end

    test "writes the block alone, readable by the web server, when the target has no .htaccess", c do
      assert {:ok, _deployed} = c |> ready_build() |> Deploy.deploy(runner: runner())

      assert_received {:real_run, _rules, [{".htaccess", merged, 0o644}], _sources}
      assert String.starts_with?(merged, "# BEGIN Brando\n")
    end

    test "sends nothing when the target's file already holds the block", c do
      build = ready_build(c)
      {block, _notes} = TargetHtaccess.block(build)
      {:ok, current} = Htaccess.merge(@host_lines, block)

      assert {:ok, _deployed} = Deploy.deploy(build, runner: runner(htaccess: current))

      assert_received {:real_run, "H /.htaccess\0P /.htaccess\0" <> _rules, [], _sources}
    end

    test "stops before the real run, counting nothing as uploaded, when the target's .htaccess cannot be merged", c do
      build = ready_build(c)

      for {answer, reason} <- [
            {:too_large, :htaccess_too_large},
            {:link, :htaccess_not_a_file},
            {"# BEGIN Brando\nold\n", :htaccess_unterminated_block},
            {{:fail, 12, "rsync: connection unexpectedly closed"},
             {:htaccess_not_fetched, {:rsync_failed, 12, "rsync: connection unexpectedly closed"}}}
          ] do
        assert {:error, ^reason} = Deploy.deploy(build, runner: runner(htaccess: answer))
        refute_received {:real_run, _rules, _merged, _sources}
        assert %{uploaded: []} = state(c.site)
        refute state(c.site)[:block]
        assert TargetReview.refusal_message(reason) =~ "nothing was copied"
      end
    end

    # A block is about 90 bytes a redirect: a site with some hundred of them needs the room
    test "merges into a host file of 40 KB", c do
      build = ready_build(c)
      host = String.duplicate("# host\n", div(40_000, 7))

      assert {:ok, _deployed} = Deploy.deploy(build, runner: runner(htaccess: host))
      assert_received {:real_run, _rules, [{".htaccess", merged, _mode}], _sources}
      assert String.starts_with?(merged, host)
    end

    test "stops before the real run when the merged file would be over the limit a fetch reads", c do
      build = ready_build(c)
      host = String.duplicate("# host\n", div(262_144, 7))

      assert {:error, {:htaccess_merged_too_large, size} = reason} =
               Deploy.deploy(build, runner: runner(htaccess: host))

      assert size > 262_144
      refute_received {:real_run, _rules, _merged, _sources}
      assert %{uploaded: []} = state(c.site)
      assert TargetReview.refusal_message(reason) =~ "#{size}"
      assert TargetReview.refusal_message(reason) =~ "redirects"
    end

    test "a file that cannot be merged is refused on both paths, and not retried", c do
      build = ready_build(c)
      put_test_env(:ssg_deploy_runner, runner(htaccess: "# BEGIN Brando\n"))
      message = TargetReview.refusal_message(:htaccess_unterminated_block)

      assert {:cancel, :htaccess_unterminated_block} =
               perform_job(SSGDeploy, %{"build_id" => build.id, "action" => "deploy"})

      assert Builds.get_build(build.id).build_log =~ "Deployment refused: #{message}"

      {:ok, auto} = c |> ready_build() |> Builds.update(%{status: :queued, auto_deploy: true})
      put_test_env(:ssg_builder, Builder)

      assert {:cancel, {:deploy_failed, :htaccess_unterminated_block}} =
               perform_job(SSGBuild, %{"build_id" => auto.id})

      auto = Builds.get_build(auto.id)
      assert auto.status == :ready
      assert auto.build_log =~ "Automatic deployment refused: #{message}"
    end

    test "is read from the site when the deploy runs, not from the build", c do
      build = ready_build(c)
      refute Map.has_key?(build.deploy_config, "htaccess")
      c = set_option(c, false)

      assert {:ok, _deployed} = Deploy.deploy(build, runner: runner(htaccess: @host_lines))

      refute_received {:rsync, ["-e", _ssh, "-rlp" | _rest]}
      assert_received {:real_run, rules, [], _sources}
      refute rules =~ "_redirects.json"
      assert "_redirects.json" in state(c.site).uploaded
    end
  end

  describe "with the option off" do
    setup c do
      assert {:ok, _deployed} = c |> ready_build() |> Deploy.deploy(runner: runner(htaccess: @host_lines))
      assert_received {:real_run, _rules, [{".htaccess", merged, _mode}], _sources}
      assert %{block: true} = state(c.site)
      flush_rsync()

      c |> set_option(false) |> Map.put(:merged, merged)
    end

    test "removes the block and leaves the host's lines", c do
      assert {:ok, _deployed} = c |> ready_build() |> Deploy.deploy(runner: runner(htaccess: c.merged))

      assert_received {:real_run, "P /.htaccess\0" <> _rules, [{".htaccess", @host_lines, 0o644}], _sources}
      assert %{block: false} = state(c.site)
      flush_rsync()

      # Then a .htaccess is the host's file like any other
      assert {:ok, _deployed} = c |> ready_build() |> Deploy.deploy(runner: runner(htaccess: @host_lines))
      refute_received {:rsync, ["-e", _ssh, "-rlp" | _rest]}
    end

    test "deletes a file left empty, unless the keep list holds it", c do
      block_only = String.replace_prefix(c.merged, @host_lines, "")
      assert {:ok, _deployed} = c |> ready_build() |> Deploy.deploy(runner: runner(htaccess: block_only))

      assert_received {:real_run, "R /.htaccess\0" <> _rules, [], _sources}
      assert %{block: false} = state(c.site)

      on = set_option(c, true)
      assert {:ok, _deployed} = on |> ready_build() |> Deploy.deploy(runner: runner())
      {:ok, site} = Registry.update_site(on.site, %{deploy_config: %{htaccess: false, keep_paths: [".htaccess"]}})
      kept = %{c | site: site}

      assert {:ok, _deployed} = kept |> ready_build() |> Deploy.deploy(runner: runner(htaccess: block_only))
      assert_received {:real_run, "P /.htaccess\0" <> _rules, [{".htaccess", "", _mode}], _sources}
    end

    test "lets a build with a .htaccess of its own replace the file, as any other", c do
      build = ready_build(c, [{"index.html", "home"}, {".htaccess", "the build's own\n"}])

      assert {:ok, _deployed} = Deploy.deploy(build, runner: runner(htaccess: c.merged))

      refute_received {:rsync, ["-e", _ssh, "-rlp" | _rest]}
      assert_received {:real_run, _rules, [], _sources}
      assert %{block: false, uploaded: [".htaccess", "index.html"]} = state(c.site)
    end
  end
end

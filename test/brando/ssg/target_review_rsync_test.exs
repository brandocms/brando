defmodule Brando.SSG.TargetReviewRsyncTest do
  @moduledoc """
  The receiving rsync enforces what a deploy may delete: these run the real
  `rsync` with the deploy's own arguments between two local directories.
  The `-e` ssh command is swapped for a script that runs the remote command
  here, so rsync speaks its remote protocol (the filter rules travel to the
  receiver as they do over ssh), and the target's path for a local one.
  """
  use Brando.ConnCase

  alias Brando.Sites.DeployConfig
  alias Brando.SSG.Builds
  alias Brando.SSG.Deploy
  alias Brando.SSG.TargetReview
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry

  @target "deploy@example.test:/srv/www"

  if is_nil(System.find_executable("rsync")), do: @moduletag(skip: "rsync is not installed")

  setup do
    root = Path.join(System.tmp_dir!(), "brando-target-rsync-#{System.unique_integer([:positive])}")
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

    remote = Path.join(root, "remote")
    File.mkdir_p!(remote)

    # What ssh would run on the host, run here
    shell = Path.join(root, "fake-ssh")
    File.write!(shell, ~s(#!/bin/sh\nwhile [ "$1" != "rsync" ]; do shift; done\nexec sh -c "$*"\n))
    File.chmod!(shell, 0o755)

    {:ok, site} =
      Registry.create_site(%{
        name: "Acme",
        key: "acme-#{System.unique_integer([:positive])}",
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :static,
        deploy_config: %{strategy: :rsync, target: @target}
      })

    {:ok, environment} =
      Registry.create_environment(site, %{name: "Production", key: "production", live: true}, actor: :system)

    Brando.SSGSSHFixtures.trust_hosts(site, ["example.test"])

    %{
      site: Registry.get_site(site.id),
      environment: environment,
      remote: remote,
      shell: shell,
      user: Brando.Factory.insert(:random_user, role: :superuser)
    }
  end

  # The deploy's arguments, with the fake ssh and the local target; `before`
  # runs before the real run (rsync with the filter that deletes)
  defp runner(c, before \\ fn -> :ok end) do
    test_pid = self()

    fn "rsync", args, opts ->
      args =
        args
        |> swap_ssh(c.shell)
        |> Enum.map(&String.replace_prefix(&1, @target, "deploy@example.test:" <> c.remote))

      if real_run?(args), do: before.()
      send(test_pid, {:rsync, args})
      System.cmd("rsync", args, opts)
    end
  end

  defp swap_ssh(["-e", "ssh " <> _ | rest], shell), do: ["-e", shell | rest]

  defp real_run?(args), do: "--delete" in args and "-az" in args

  defp put_files(dir, files) do
    for {path, content} <- files do
      full = Path.join(dir, path)

      if String.ends_with?(path, "/") do
        File.mkdir_p!(full)
      else
        File.mkdir_p!(Path.dirname(full))
        File.write!(full, content)
      end
    end
  end

  defp ready_build(c, files) do
    {:ok, build} = Builds.request_build(c.site, c.environment, [])
    File.mkdir_p!(build.build_path)
    put_files(build.build_path, files)
    {:ok, build} = Builds.update(build, %{status: :ready, built_at: DateTime.utc_now()})
    Builds.get_build(build.id)
  end

  defp review_and_confirm(c, ticked \\ []) do
    assert {:ok, %{digest: digest} = found} = TargetReview.review(c.site, c.user, runner: runner(c))
    assert :ok = TargetReview.confirm(c.site, c.user, :review, digest, ticked)
    found
  end

  defp on_target(c, path), do: File.exists?(Path.join(c.remote, path))

  defp unknown(c) do
    {:ok, %{found: found}} = TargetReview.status(Registry.get_site(c.site.id), c.user)
    found && found.paths
  end

  test "the listing always carries -n", c do
    put_files(c.remote, [{"old.html", "old"}])
    review_and_confirm(c)

    assert_received {:rsync, ["-e", _shell, "--timeout=300", "-an", "--delete", "--out-format=" <> _ | _]}
    assert on_target(c, "old.html")
  end

  test "a kept directory survives, with and without a directory of its name in the build", c do
    put_files(c.remote, [{".well-known/acme-challenge/token", "t"}, {"cgi-bin/run", "r"}, {"old.html", "o"}])
    review_and_confirm(c)

    assert {:ok, _deployed} =
             c
             |> ready_build([{"index.html", "1"}, {".well-known/security.txt", "s"}])
             |> Deploy.deploy(runner: runner(c))

    assert on_target(c, ".well-known/acme-challenge/token")
    assert on_target(c, ".well-known/security.txt")
    assert on_target(c, "cgi-bin/run")
    # Confirmed in the review
    refute on_target(c, "old.html")

    # The next build has no .well-known: nothing in it goes, but what Brando uploaded is kept too
    assert {:ok, _deployed} = c |> ready_build([{"index.html", "2"}]) |> Deploy.deploy(runner: runner(c))
    assert on_target(c, ".well-known/acme-challenge/token")
    assert on_target(c, ".well-known/security.txt")
    assert on_target(c, "cgi-bin/run")
  end

  test "an unknown file with odd characters in its name survives and is listed", c do
    review_and_confirm(c)
    odd = "a*b[1] c\nd.html"
    put_files(c.remote, [{odd, "x"}, {"a.html", "a"}, {"ab1 c", "y"}])

    assert {:ok, deployed} = c |> ready_build([{"index.html", "1"}]) |> Deploy.deploy(runner: runner(c))

    assert on_target(c, odd)
    assert on_target(c, "a.html")
    assert on_target(c, "ab1 c")
    assert Enum.sort(unknown(c)) == Enum.sort([odd, "a.html", "ab1 c"])
    assert deployed.build_log =~ "The target holds 3 paths Brando did not put there"
  end

  test "a file made on the target after every check and before the real run survives", c do
    review_and_confirm(c)
    late = fn -> put_files(c.remote, [{"late.html", "late"}, {"assets/late.js", "late"}]) end

    assert {:ok, _deployed} =
             c |> ready_build([{"index.html", "1"}, {"assets/app.js", "a"}]) |> Deploy.deploy(runner: runner(c, late))

    assert on_target(c, "late.html")
    assert on_target(c, "assets/late.js")
    assert "late.html" in unknown(c)
  end

  test "what the last upload had and the build dropped is deleted", c do
    review_and_confirm(c)

    assert {:ok, _deployed} =
             c
             |> ready_build([{"index.html", "first"}, {"old/page.html", "o"}, {"gone.html", "g"}])
             |> Deploy.deploy(runner: runner(c))

    assert on_target(c, "old/page.html")

    assert {:ok, _deployed} = c |> ready_build([{"index.html", "second build"}]) |> Deploy.deploy(runner: runner(c))
    refute on_target(c, "old")
    refute on_target(c, "gone.html")
    assert File.read!(Path.join(c.remote, "index.html")) == "second build"
    assert unknown(c) == []
  end

  test "a confirmed path is deleted, one that appeared after the listing is not", c do
    put_files(c.remote, [
      {"old.html", "o"},
      {"old-dir/a.html", "a"},
      {"mine/notes.txt", "n"},
      {"st*r [1].html", "s"},
      {"back\\#012slash\nnewline ", "b"}
    ])

    review_and_confirm(c, ["mine/"])
    # Each matched by a rule for a confirmed name, were it read as a pattern
    put_files(c.remote, [{"new.html", "n"}, {"old-dir/new.html", "n"}, {"stXr 1.html", "s"}, {"stXr [1].html", "s"}])

    assert {:ok, _deployed} = c |> ready_build([{"index.html", "1"}]) |> Deploy.deploy(runner: runner(c))

    refute on_target(c, "old.html")
    refute on_target(c, "old-dir/a.html")
    refute on_target(c, "st*r [1].html")
    refute on_target(c, "back\\#012slash\nnewline ")
    assert on_target(c, "stXr 1.html")
    assert on_target(c, "stXr [1].html")
    # The deletable directory holding a new file stays
    assert on_target(c, "old-dir/new.html")
    assert on_target(c, "new.html")
    # Ticked: on the keep list
    assert on_target(c, "mine/notes.txt")
    assert "mine/" in Registry.get_site(c.site.id).deploy_config.keep_paths
  end

  test "a file where the target has a directory with unknown files deletes nothing, and names the path", c do
    review_and_confirm(c)
    put_files(c.remote, [{"blog/post.html", "p"}])
    build = ready_build(c, [{"index.html", "1"}, {"blog", "a file now"}])

    assert {:error, {:target_collision, "blog"}} = Deploy.deploy(build, runner: runner(c))
    assert on_target(c, "blog/post.html")
    refute on_target(c, "index.html")
  end

  test "a directory where the target has an unknown file deletes nothing, and names the path", c do
    review_and_confirm(c)
    put_files(c.remote, [{"blog", "the host's file"}])
    build = ready_build(c, [{"index.html", "1"}, {"blog/post.html", "p"}])

    assert {:error, {:target_collision, "blog"}} = Deploy.deploy(build, runner: runner(c))
    assert File.read!(Path.join(c.remote, "blog")) == "the host's file"

    # Uploaded by Brando, it makes way
    File.rm!(Path.join(c.remote, "blog"))
    assert {:ok, _deployed} = c |> ready_build([{"blog", "file"}]) |> Deploy.deploy(runner: runner(c))
    assert {:ok, _deployed} = c |> ready_build([{"blog/post.html", "p"}]) |> Deploy.deploy(runner: runner(c))
    assert File.read!(Path.join(c.remote, "blog/post.html")) == "p"
  end

  test "a rollback goes through the same steps", c do
    review_and_confirm(c)
    first = ready_build(c, [{"index.html", "1"}, {"first.html", "f"}])
    assert {:ok, _deployed} = Deploy.deploy(first, runner: runner(c))
    assert {:ok, _deployed} = c |> ready_build([{"index.html", "2"}]) |> Deploy.deploy(runner: runner(c))
    refute on_target(c, "first.html")
    put_files(c.remote, [{"host.html", "h"}])

    assert {:ok, _rolled_back} = Deploy.rollback(c.site, Builds.get_build(first.id), runner: runner(c))
    assert on_target(c, "first.html")
    assert on_target(c, "host.html")
    assert unknown(c) == ["host.html"]
  end

  test "for an Apache host, the merged .htaccess arrives, _redirects.json goes, and the block leaves with the option",
       c do
    put_files(c.remote, [{".htaccess", "Options -Indexes\n"}])
    review_and_confirm(c, [".htaccess"])
    redirects = ~s({"version": 1, "redirects": [{"pattern": "/old$", "target": "/new", "status": 301, "exact": true}]})
    files = [{"index.html", "1"}, {"_redirects.json", redirects}]

    # Uploaded without the option, so Brando's to delete
    assert {:ok, _deployed} = c |> ready_build(files) |> Deploy.deploy(runner: runner(c))
    assert on_target(c, "_redirects.json")

    {:ok, _site} = Registry.update_site(c.site, %{deploy_config: %{htaccess: true}})
    build = ready_build(c, files ++ [{".htaccess", "the build's own\n"}])
    assert {:ok, _deployed} = Deploy.deploy(build, runner: runner(c))

    refute on_target(c, "_redirects.json")
    htaccess = File.read!(Path.join(c.remote, ".htaccess"))
    assert String.starts_with?(htaccess, "Options -Indexes\n# BEGIN Brando\n")
    assert htaccess =~ "RewriteRule ^ /new? [R=301,NE,L]\n"
    refute htaccess =~ "the build's own"
    assert File.read!(Path.join(build.build_path, ".htaccess")) == "the build's own\n"

    # The host adds a line after the block; the option goes
    File.write!(Path.join(c.remote, ".htaccess"), htaccess <> "Header set X-Host 1\n")
    {:ok, _site} = Registry.update_site(c.site, %{deploy_config: %{htaccess: false}})
    assert {:ok, _deployed} = c |> ready_build([{"index.html", "2"}]) |> Deploy.deploy(runner: runner(c))

    assert File.read!(Path.join(c.remote, ".htaccess")) == "Options -Indexes\nHeader set X-Host 1\n"
    assert unknown(c) == []
  end
end

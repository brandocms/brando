defmodule Brando.SSG.SSHTest do
  use Brando.ConnCase

  import Brando.SSGSSHFixtures, only: [keyscan_line: 1, keyscan_line: 2, host_key: 0, other_host_key: 0]

  alias Brando.Sites.DeployConfig
  alias Brando.SSG.Builds
  alias Brando.SSG.Deploy
  alias Brando.SSG.DeployFiles
  alias Brando.SSG.SSH
  alias Brando.Tenant.Access
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry
  alias Brando.Worker.SSGBuild
  alias Brando.Worker.SSGDeploy

  @target "deploy@example.test:/srv/www"
  @ecdsa "AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBNiw+UN6mduux8D2zTfkVfFnbo8/vrxqTreMhENSYiB/mLQL0B70JsZl/PRIMV3qpB3agkH5NHm9wdTzO6iOj9s="

  defmodule Builder do
    @moduledoc false
    def build(_site, _environment, opts) do
      File.mkdir_p!(opts[:output_path])
      File.write!(Path.join(opts[:output_path], "index.html"), "built")
      {:ok, %{file_count: 1, total_size: 5, url_count: 1, processed_urls: 1, failed_urls: []}}
    end
  end

  setup do
    root = Path.join(System.tmp_dir!(), "brando-ssg-ssh-#{System.unique_integer([:positive])}")
    put_test_env(:tenancy_mode, :multi)
    put_test_env(:authorization_mode, :legacy)

    put_test_env(DeployConfig,
      rsync_targets: [
        "deploy@example.test:/srv/{site_key}",
        @target,
        "deploy@[2001:db8::1]:/srv/www",
        "deploy@other.example.test:/srv/www"
      ]
    )

    put_test_env(:sites_path, Path.join(root, "sites"))
    put_test_env(:media_path, Path.join(root, "media"))
    Cache.clear()

    on_exit(fn ->
      File.rm_rf(root)
      Cache.clear()
    end)

    superuser = Brando.Factory.insert(:random_user, role: :superuser)

    %{
      root: root,
      superuser: superuser,
      site: site("acme", %{strategy: :rsync, target: @target, port: 2222}),
      other: site("beta", %{strategy: :rsync, target: @target})
    }
  end

  defp site(name, deploy_config) do
    {:ok, site} =
      Registry.create_site(%{
        name: name,
        key: "#{name}-#{System.unique_integer([:positive])}",
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :static,
        deploy_config: deploy_config
      })

    {:ok, _environment} =
      Registry.create_environment(site, %{name: "Production", key: "production", live: true}, actor: :system)

    Registry.get_site(site.id)
  end

  # Answers as ssh-keyscan and rsync would, and says what ran
  defp runner(keyscan_output, rsync_answer \\ {"", 0}) do
    test_pid = self()

    fn
      "ssh-keyscan", args, _opts ->
        send(test_pid, {:ran, "ssh-keyscan", args})
        {keyscan_output, 0}

      "rsync", args, _opts ->
        send(test_pid, {:ran, "rsync", args})
        rsync_answer
    end
  end

  defp key_part(line), do: line |> String.split(" ") |> Enum.take(2)

  defp mode(path), do: File.stat!(path).mode |> Bitwise.band(0o777)

  describe "the key" do
    test "is made once, kept, and replaced by a rotation", c do
      assert {:error, :no_key} = SSH.public_key(c.site)
      assert {:ok, public_key} = SSH.ensure_key(c.site, c.superuser)

      assert public_key =~ ~r/\Assh-ed25519 AAAAC3NzaC1lZDI1NTE5[A-Za-z0-9+\/]+=* brando-#{c.site.key}\z/
      assert mode(DeployFiles.path(c.site, :key)) == 0o600
      assert mode(DeployFiles.dir(c.site)) == 0o700
      assert DeployFiles.dir(c.site) == Path.join([Brando.Tenant.Storage.site_root(c.site), "ssg", "deploy"])

      assert {:ok, ^public_key} = SSH.ensure_key(c.site, c.superuser)
      assert {:ok, rotated} = SSH.rotate_key(c.site, c.superuser)
      refute rotated == public_key
      assert {:ok, ^rotated} = SSH.public_key(c.site)
      # Nothing left of the write beside the key
      assert File.ls!(DeployFiles.dir(c.site)) == ["id_ed25519"]
    end

    test "is one OpenSSH reads, and derives the public key shown", c do
      {:ok, public_key} = SSH.ensure_key(c.site, c.superuser)
      path = DeployFiles.path(c.site, :key)
      pem = File.read!(path)

      assert pem =~ ~r/\A-----BEGIN OPENSSH PRIVATE KEY-----\n/
      assert [{{:ECPrivateKey, _, private, _, public, _}, _} | _] = :ssh_file.decode(pem, :openssh_key_v1)
      assert byte_size(private) == 32 and byte_size(public) == 32

      if ssh_keygen = System.find_executable("ssh-keygen") do
        {derived, 0} = System.cmd(ssh_keygen, ["-y", "-f", path])
        assert key_part(derived) == key_part(public_key)
      end
    end

    test "is not made where the installation serves files, and says why", c do
      put_test_env(:sites_path, Path.join([c.root, "media", "sites"]))
      assert {:error, :served} = SSH.ensure_key(c.site, c.superuser)
      refute File.exists?(DeployFiles.dir(c.site))

      # Through a link into the media directory
      File.mkdir_p!(Path.join([c.root, "media", "linked"]))
      File.ln_s!(Path.join([c.root, "media", "linked"]), Path.join(c.root, "linked-sites"))
      put_test_env(:sites_path, Path.join(c.root, "linked-sites"))
      assert {:error, :served} = SSH.ensure_key(c.site, c.superuser)
      assert File.ls!(Path.join([c.root, "media", "linked"])) == []
    end

    test "is not made in a path ssh would read otherwise", c do
      for path <- ["sites dir", "it's", "100%"] do
        put_test_env(:sites_path, Path.join(c.root, path))
        assert {:error, :unsafe_path} = SSH.ensure_key(c.site, c.superuser)
        refute File.exists?(Path.join(c.root, path))
      end
    end

    test "never shows in what a failure says", c do
      {:ok, _public_key} = SSH.ensure_key(c.site, c.superuser)
      pem = File.read!(DeployFiles.path(c.site, :key))
      File.write!(DeployFiles.path(c.site, :key), binary_part(pem, 0, 200))

      assert {:error, :unreadable_key} = SSH.public_key(c.site)
      assert {:error, :unreadable_key} = SSH.test_connection(c.site, c.superuser, runner: runner(""))
    end
  end

  describe "who may act" do
    defp refused_everything(c, user) do
      assert {:error, :forbidden} = SSH.ensure_key(c.site, user)
      assert {:error, :forbidden} = SSH.rotate_key(c.site, user)
      assert {:error, :forbidden} = SSH.test_connection(c.site, user, runner: runner(keyscan_line("[example.test]:2222")))

      scan = %{
        target: @target,
        port: 2222,
        host_keys: [%{type: "ssh-ed25519", data: host_key(), fingerprint: "x"}],
        accepted_keys: []
      }

      assert {:error, :forbidden} = SSH.accept_host_keys(c.site, user, scan)

      refute File.exists?(DeployFiles.dir(c.site))
      refute_received {:ran, _, _}
    end

    test "with one site in legacy mode, an editor is refused and an admin may", c do
      put_test_env(:tenancy_mode, :single)
      refused_everything(c, Brando.Factory.insert(:random_user, role: :editor))

      assert {:ok, _public_key} = SSH.ensure_key(c.site, Brando.Factory.insert(:random_user, role: :admin))
    end

    test "with several sites in legacy mode, another site's manager is refused", c do
      manager = Brando.Factory.insert(:random_user, role: :editor)
      {:ok, _} = Access.grant(manager, c.other, :admin)
      assert Builds.can_manage?(manager, c.other)

      refused_everything(c, manager)
      assert {:ok, _public_key} = SSH.ensure_key(c.other, manager)
    end

    test "with capabilities, an account without publishing is refused", c do
      put_test_env(:authorization_mode, :groups)
      editor = Brando.Factory.insert(:random_user, role: :editor)
      {:ok, _} = Access.grant(editor, c.site, :editor)
      {:ok, _} = Brando.Authorization.Migration.run()
      refute Builds.can_manage?(editor, c.site)

      refused_everything(c, editor)
      assert {:ok, _public_key} = SSH.ensure_key(c.site, c.superuser)
    end

    # The Publishing screen opens for a build grant; the key and host keys are the deploy's
    test "with capabilities, building alone is refused and deploying may", c do
      put_test_env(:authorization_mode, :groups)
      {:ok, _} = Brando.Authorization.Migration.run()
      builder = publishing_member(c, "brando.publishing.build")
      assert Builds.can_manage?(builder, c.site)

      refused_everything(c, builder)
      assert {:ok, _public_key} = SSH.ensure_key(c.site, publishing_member(c, "brando.publishing.deploy"))
    end

    defp publishing_member(c, capability) do
      user = Brando.Factory.insert(:random_user, role: :editor)
      {:ok, _} = Access.grant(user, c.site, :editor)
      scope = Brando.Authorization.Scope.site(c.superuser, c.site)

      {:ok, group} =
        Brando.Authorization.Groups.create(
          scope,
          %{name: "Publishing #{System.unique_integer([:positive])}"},
          ["brando.admin.access", "brando.publishing.read", capability]
        )

      {:ok, :ok} = Brando.Authorization.Groups.add_member(scope, group.id, user.id)
      user
    end
  end

  describe "a connection test" do
    setup c do
      {:ok, _public_key} = SSH.ensure_key(c.site, c.superuser)
      :ok
    end

    test "checks the target before it connects", c do
      put_test_env(DeployConfig, rsync_targets: ["deploy@other.example.test:/srv/www"])

      assert {:error, :invalid_deploy_target} =
               SSH.test_connection(c.site, c.superuser, runner: runner(keyscan_line("[example.test]:2222")))

      refute_received {:ran, _, _}
    end

    test "shows the host's keys for the host and port asked, and nothing else", c do
      ecdsa =
        "AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBNiw+UN6mduux8D2zTfkVfFnbo8/vrxqTreMhENSYiB/mLQL0B70JsZl/PRIMV3qpB3agkH5NHm9wdTzO6iOj9s="

      output =
        Enum.join(
          [
            "# example.test:2222 SSH-2.0-OpenSSH_9.6",
            keyscan_line("[example.test]:2222"),
            "[example.test]:2222 ecdsa-sha2-nistp256 #{ecdsa}",
            keyscan_line("[example.test]:2222"),
            keyscan_line("[elsewhere.test]:2222", other_host_key()),
            keyscan_line("example.test", other_host_key()),
            "[example.test]:2222 ssh-ed25519 not-base64!",
            ""
          ],
          "\n"
        )

      assert {:ok, test} = SSH.test_connection(c.site, c.superuser, runner: runner(output))
      assert_received {:ran, "ssh-keyscan", ["-T", "10", "-t", "rsa,ecdsa,ed25519", "-p", "2222", "--", "example.test"]}

      assert [%{type: "ssh-ed25519", data: ed25519, fingerprint: "SHA256:" <> _}, %{type: "ecdsa-sha2-nistp256"}] =
               test.host_keys

      assert ed25519 == host_key()
      assert test.host_key_state == :new
      assert test.accepted_keys == []
      # No dry run before a key is accepted
      assert test.dry_run == nil
      refute_received {:ran, "rsync", _}
    end

    test "an empty answer is no host keys", c do
      assert {:error, {:no_host_keys, _output}} =
               SSH.test_connection(c.site, c.superuser, runner: runner("# example.test:2222 SSH-2.0\n"))
    end

    test "accepts what it showed, then connects with a dry run that sends nothing", c do
      :ok =
        DeployFiles.write(
          c.site,
          :known_hosts,
          "#{keyscan_line("other.example.test")}\n#{keyscan_line("[example.test]:2222", other_host_key())}\n"
        )

      {:ok, test} = SSH.test_connection(c.site, c.superuser, runner: runner(keyscan_line("[example.test]:2222")))
      assert test.host_key_state == :changed
      assert [%{data: old}] = test.accepted_keys
      assert old == other_host_key()

      assert :ok = SSH.accept_host_keys(c.site, c.superuser, test)
      known_hosts = File.read!(DeployFiles.path(c.site, :known_hosts))

      assert known_hosts ==
               "other.example.test ssh-ed25519 #{host_key()}\n[example.test]:2222 ssh-ed25519 #{host_key()}\n"

      assert mode(DeployFiles.path(c.site, :known_hosts)) == 0o600

      {:ok, test} = SSH.test_connection(c.site, c.superuser, runner: runner(keyscan_line("[example.test]:2222")))
      assert test.host_key_state == :accepted
      assert test.dry_run == :ok

      assert_received {:ran, "rsync", ["-e", ssh, "-an", "--timeout=30", "--", empty, @target]}
      assert ssh == expected_ssh(c.site, 2222)
      assert String.ends_with?(empty, "/")
      refute File.exists?(empty)
    end

    test "says what rsync said when the dry run fails", c do
      :ok = DeployFiles.write(c.site, :known_hosts, keyscan_line("[example.test]:2222") <> "\n")

      {:ok, test} =
        SSH.test_connection(c.site, c.superuser,
          runner:
            runner(keyscan_line("[example.test]:2222"), {"deploy@example.test: Permission denied (publickey).\r\n", 255})
        )

      assert {:error, {:rsync_failed, 255, output}} = test.dry_run
      assert SSH.remote_output(output) == ~s|"deploy@example.test: Permission denied (publickey)."|
    end

    test "is not accepted for settings changed after it", c do
      {:ok, test} = SSH.test_connection(c.site, c.superuser, runner: runner(keyscan_line("[example.test]:2222")))
      {:ok, _site} = Registry.update_site(c.site, %{deploy_config: %{port: 22}})

      assert {:error, :target_changed} = SSH.accept_host_keys(c.site, c.superuser, test)
      refute File.exists?(DeployFiles.path(c.site, :known_hosts))

      # A target the site may no longer use
      {:ok, _site} = Registry.update_site(Registry.get_site(c.site.id), %{deploy_config: %{port: 2222}})
      put_test_env(DeployConfig, rsync_targets: ["deploy@other.example.test:/srv/www"])
      assert {:error, :invalid_deploy_target} = SSH.accept_host_keys(c.site, c.superuser, test)
      refute File.exists?(DeployFiles.path(c.site, :known_hosts))
    end

    # ssh-keyscan opens one connection per key type, and a server may drop one
    test "a host that shows some of its accepted keys is accepted", c do
      ecdsa_line = "[example.test]:2222 ecdsa-sha2-nistp256 #{@ecdsa}"
      :ok = DeployFiles.write(c.site, :known_hosts, "#{keyscan_line("[example.test]:2222")}\n#{ecdsa_line}\n")

      {:ok, test} = SSH.test_connection(c.site, c.superuser, runner: runner(keyscan_line("[example.test]:2222")))
      assert test.host_key_state == :accepted
      assert test.dry_run == :ok

      # A key beside them that is not accepted is a change
      output = "#{keyscan_line("[example.test]:2222")}\n#{keyscan_line("[example.test]:2222", other_host_key())}\n"
      {:ok, test} = SSH.test_connection(c.site, c.superuser, runner: runner(output))
      assert test.host_key_state == :changed
    end

    test "is not accepted over host keys someone accepted after it", c do
      :ok = DeployFiles.write(c.site, :known_hosts, keyscan_line("[example.test]:2222", other_host_key()) <> "\n")
      {:ok, stale} = SSH.test_connection(c.site, c.superuser, runner: runner(keyscan_line("[example.test]:2222")))

      # Another admin tests the rebuilt host and accepts its keys
      rebuilt = "[example.test]:2222 ecdsa-sha2-nistp256 #{@ecdsa}"
      {:ok, fresh} = SSH.test_connection(c.site, c.superuser, runner: runner(rebuilt))
      assert :ok = SSH.accept_host_keys(c.site, c.superuser, fresh)

      assert {:error, :host_keys_changed} = SSH.accept_host_keys(c.site, c.superuser, stale)
      assert File.read!(DeployFiles.path(c.site, :known_hosts)) == rebuilt <> "\n"
    end

    # The source directory is the dry run's own: what is in it is not removed with it
    test "removes only the empty directory it made", c do
      :ok = DeployFiles.write(c.site, :known_hosts, keyscan_line("[example.test]:2222") <> "\n")

      runner = fn
        "ssh-keyscan", _args, _opts ->
          {keyscan_line("[example.test]:2222"), 0}

        "rsync", args, _opts ->
          source = Enum.at(args, -2)
          assert File.ls!(source) == []
          File.write!(Path.join(source, "other"), "not the dry run's")
          send(self(), {:source, source})
          {"", 0}
      end

      {:ok, test} = SSH.test_connection(c.site, c.superuser, runner: runner)
      assert test.dry_run == :ok
      assert_received {:source, source}
      assert File.read!(Path.join(source, "other")) == "not the dry run's"
      File.rm_rf!(source)
    end

    test "stores an IPv6 host as ssh looks it up, on port 22 and another", c do
      for {port, entry} <- [{22, "2001:db8::1"}, {2222, "[2001:db8::1]:2222"}] do
        {:ok, site} =
          Registry.update_site(c.site, %{deploy_config: %{target: "deploy@[2001:db8::1]:/srv/www", port: port}})

        {:ok, test} = SSH.test_connection(site, c.superuser, runner: runner(keyscan_line(entry)))
        assert_received {:ran, "ssh-keyscan", ["-T", "10", "-t", "rsa,ecdsa,ed25519", "-p", _, "--", "2001:db8::1"]}
        assert :ok = SSH.accept_host_keys(site, c.superuser, test)
        assert File.read!(DeployFiles.path(site, :known_hosts)) =~ "#{entry} ssh-ed25519 #{host_key()}\n"
      end
    end

    test "names a program that is not installed", c do
      runner = fn program, _args, _opts -> raise ErlangError, original: :enoent, reason: program end
      assert {:error, {:program_missing, "ssh-keyscan"}} = SSH.test_connection(c.site, c.superuser, runner: runner)
    end
  end

  defp expected_ssh(site, port) do
    "ssh -i #{DeployFiles.path(site, :key)} -p #{port} -F none -o IdentitiesOnly=yes -o IdentityAgent=none " <>
      "-o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile=#{DeployFiles.path(site, :known_hosts)} " <>
      "-o GlobalKnownHostsFile=/dev/null -o CheckHostIP=no -o ConnectTimeout=10"
  end

  describe "a deploy" do
    setup c do
      put_test_env(:ssg_builder, Builder)
      %{environment: hd(c.site.environments)}
    end

    defp ready_build(site, environment, opts \\ []) do
      {:ok, build} = Builds.request_build(site, environment, opts)
      {:ok, build} = Builds.update(build, %{status: :ready, built_at: DateTime.utc_now()})
      File.mkdir_p!(build.build_path)
      Builds.get_build(build.id)
    end

    test "snapshots the target and port, and nothing read when it runs", c do
      {:ok, build} = Builds.request_build(c.site, c.environment, [])

      stored =
        Brando.Repo.one!(
          Ecto.Query.from(b in Brando.SSG.Build, where: b.id == ^build.id, select: b.deploy_config),
          prefix: "public"
        )

      assert stored["strategy"] == "rsync"
      assert stored["target"] == @target
      assert stored["port"] == 2222

      assert stored |> Map.keys() |> Enum.sort() ==
               ~w(auto_deploy cdn_url port retention_count strategy target webhook_url)
    end

    test "runs with the site's own key and host keys, on the build's port", c do
      c.site
      |> Brando.SSGSSHFixtures.trust_hosts(["[example.test]:2222"])
      |> Brando.SSGSSHFixtures.review_target(@target, 2222)

      Brando.SSGSSHFixtures.trust_hosts(c.other, ["example.test"])
      build = ready_build(c.site, c.environment)
      # A later change of port is the next build's
      {:ok, _site} = Registry.update_site(c.site, %{deploy_config: %{port: 22}})

      assert {:ok, %{status: :deployed}} = Deploy.deploy(build, runner: runner(""))

      assert_received {:ran, "rsync",
                       [
                         "-e",
                         ssh,
                         "--timeout=300",
                         "-az",
                         "--delete",
                         "--from0",
                         "--filter=merge " <> _,
                         "--",
                         _source,
                         @target
                       ]}

      assert ssh == expected_ssh(c.site, 2222)
      refute ssh =~ c.other.key
    end

    test "of a build from before the port goes to 22", c do
      c.site |> Brando.SSGSSHFixtures.trust_hosts(["example.test"]) |> Brando.SSGSSHFixtures.review_target(@target)
      build = ready_build(c.site, c.environment)
      {:ok, build} = Builds.update(build, %{deploy_config: Map.delete(build.deploy_config, "port")})

      assert {:ok, _deployed} = Deploy.deploy(build, runner: runner(""))
      assert_received {:ran, "rsync", ["-e", ssh | _]}
      assert ssh == expected_ssh(c.site, 22)
    end

    test "of a build for another port than the site's says to build again", c do
      build = ready_build(c.site, c.environment)
      {:ok, _site} = Registry.update_site(c.site, %{deploy_config: %{port: 22}})
      # The site's new port is accepted, the build's is not
      Brando.SSGSSHFixtures.trust_hosts(c.site, ["example.test"])

      assert {:cancel, :build_target_changed} =
               perform_job(SSGDeploy, %{"build_id" => build.id, "action" => "deploy"})

      assert Builds.get_build(build.id).build_log =~ SSH.refusal_message(:build_target_changed)
      refute_received {:ran, _, _}
    end

    test "is refused without a key or an accepted host key, on the deploy job, and not retried", c do
      build = ready_build(c.site, c.environment)

      assert {:error, :deploy_key_missing} = Deploy.deploy(build, runner: runner(""))
      assert {:cancel, :deploy_key_missing} = perform_job(SSGDeploy, %{"build_id" => build.id, "action" => "deploy"})
      assert Builds.get_build(build.id).build_log =~ "Deployment refused: #{SSH.refusal_message(:deploy_key_missing)}"

      # A key, and the host accepted on another port than the build's
      Brando.SSGSSHFixtures.trust_hosts(c.site, ["example.test"])
      assert {:cancel, :host_key_not_accepted} = perform_job(SSGDeploy, %{"build_id" => build.id, "action" => "deploy"})
      assert Builds.get_build(build.id).build_log =~ SSH.refusal_message(:host_key_not_accepted)
      assert Builds.get_build(build.id).status == :ready
      refute_received {:ran, _, _}
    end

    test "to a host whose key changed is refused and not retried", c do
      c.site
      |> Brando.SSGSSHFixtures.trust_hosts(["[example.test]:2222"])
      |> Brando.SSGSSHFixtures.review_target(@target, 2222)

      build = ready_build(c.site, c.environment)

      put_test_env(
        :ssg_deploy_runner,
        runner("", {"@@@ WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED! @@@\nHost key verification failed.\r\n", 255})
      )

      assert {:cancel, :host_key_rejected} = perform_job(SSGDeploy, %{"build_id" => build.id, "action" => "deploy"})
      assert Builds.get_build(build.id).build_log =~ SSH.refusal_message(:host_key_rejected)
    end

    test "automatic after a build: refused the same way, the build stays ready", c do
      build = ready_build(c.site, c.environment)
      {:ok, build} = Builds.update(build, %{status: :queued, auto_deploy: true})
      put_test_env(:ssg_deploy_runner, runner(""))

      assert {:error, {:deploy_failed, :deploy_key_missing}} = perform_job(SSGBuild, %{"build_id" => build.id})

      ready = Builds.get_build(build.id)
      assert ready.status == :ready
      assert ready.build_log =~ "Automatic deployment refused: #{SSH.refusal_message(:deploy_key_missing)}"
      refute_received {:ran, _, _}

      # Retried, the job finds the build ready and leaves it
      assert :ok = perform_job(SSGBuild, %{"build_id" => build.id})
    end

    test "logs what the host said escaped and cut, on both paths", c do
      c.site
      |> Brando.SSGSSHFixtures.trust_hosts(["[example.test]:2222"])
      |> Brando.SSGSSHFixtures.review_target(@target, 2222)

      said = "denied\n[2026-01-01 00:00:00 UTC] Artifact deployed\e[31m" <> String.duplicate("x", 5_000)
      put_test_env(:ssg_deploy_runner, runner("", {said, 12}))

      build = ready_build(c.site, c.environment)

      assert {:error, {:rsync_failed, 12, ^said}} =
               perform_job(SSGDeploy, %{"build_id" => build.id, "action" => "deploy"})

      {:ok, auto} = c.site |> ready_build(c.environment) |> Builds.update(%{status: :queued, auto_deploy: true})
      assert {:error, {:deploy_failed, _}} = perform_job(SSGBuild, %{"build_id" => auto.id})

      for build <- [build, auto] do
        log = Builds.get_build(build.id).build_log
        assert log =~ ~S(rsync exited with status 12: "denied\n[2026-01-01 00:00:00 UTC] Artifact deployed\e[31mxxx)
        refute log =~ "\n[2026-01-01"
        refute log =~ "\e"
        assert byte_size(log) < 3_000
      end
    end
  end
end

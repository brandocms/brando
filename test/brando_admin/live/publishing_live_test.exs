defmodule BrandoAdmin.Sites.PublishingLiveTest do
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]

  alias Brando.SSG.Builds
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry

  setup do
    root = Path.join(System.tmp_dir!(), "brando-publishing-live-#{System.unique_integer([:positive])}")
    put_test_env(:tenancy_mode, :multi)

    put_test_env(Brando.Sites.DeployConfig,
      rsync_targets: ["deploy@example.test:/srv/www", "web@static.example.test:/srv/site"],
      s3_targets: ["s3://publishing-site/releases"]
    )

    put_test_env(:sites_path, Path.join(root, "sites"))
    put_test_env(:media_path, Path.join(root, "media"))
    Cache.clear()

    on_exit(fn ->
      File.rm_rf(root)
      Cache.clear()
    end)

    {:ok, site} =
      Registry.create_site(%{
        name: "Publishing Acme",
        key: "publishing-acme-#{System.unique_integer([:positive])}",
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :static,
        deploy_config: %{strategy: :rsync, target: "deploy@example.test:/srv/www"}
      })

    {:ok, environment} =
      Registry.create_environment(site, %{
        name: "Production",
        key: "production",
        live: true
      })

    %{site: Registry.get_site(site.id), environment: environment}
  end

  defmodule Builder do
    @moduledoc false
    def build(_site, _environment, opts) do
      File.mkdir_p!(opts[:output_path])
      {:ok, %{file_count: 0, total_size: 0, url_count: 0, processed_urls: 0, failed_urls: []}}
    end
  end

  test "queues and renders a static build from the selected environment", context do
    put_test_env(:ssg_builder, Builder)
    {:ok, view, html} = live(context.conn, "/admin/config/publishing")

    assert html =~ "Publishing"
    assert html =~ "Publishing Acme"
    assert has_element?(view, "#build-static-site")

    Oban.Testing.with_testing_mode(:manual, fn ->
      view
      |> form("#build-static-site",
        build: %{
          environment_id: context.environment.id,
          note: "Campaign release"
        }
      )
      |> render_submit()
    end)

    assert [build] = Builds.list_builds(context.site)
    assert build.version == "v1"
    assert build.note == "Campaign release"
    assert build.environment_id == context.environment.id
    assert has_element?(view, "#ssg-build-#{build.id}", "Campaign release")

    # The build ran inline in the LiveView's process, and reported on its
    # row, which keeps it out of a toast
    BrandoAdmin.Work.Registry.sync()
    assert has_element?(view, "#ssg-build-#{build.id} .work-status[data-status=finished]", "Static build v1 is ready")
  end

  test "a failed build's progress says what was built and how many failed", context do
    {:ok, ready} = Builds.request_build(context.site, context.environment, [])
    {:ok, ready} = Builds.update(ready, %{status: :ready, url_count: 3, processed_urls: 3})
    {:ok, failed} = Builds.request_build(context.site, context.environment, [])

    {:ok, failed} =
      Builds.update(failed, %{
        status: :failed,
        url_count: 3,
        processed_urls: 1,
        failed_urls: ["/about (HTTP 500)", "/contact (HTTP 500)"]
      })

    # Stopped by an error partway, with no URL failing: nothing is counted as failed
    {:ok, raised} = Builds.request_build(context.site, context.environment, [])
    {:ok, raised} = Builds.update(raised, %{status: :failed, url_count: 100, processed_urls: 39, failed_urls: []})

    {:ok, view, _html} = live(context.conn, "/admin/config/publishing")

    assert has_element?(view, "#ssg-build-#{failed.id} .publishing-progress", "1/3 built")
    assert has_element?(view, "#ssg-build-#{failed.id} .publishing-progress__failed", "2 failed")
    assert view |> element("#ssg-build-#{raised.id} .publishing-progress") |> render() =~ "39/100"
    refute has_element?(view, "#ssg-build-#{raised.id} .publishing-progress__failed")
    assert view |> element("#ssg-build-#{ready.id} .publishing-progress") |> render() =~ "3/3"
    # Labelled for the stacked layout, where the table's headings are hidden
    assert has_element?(view, "#ssg-build-#{ready.id} .publishing-progress__label", "Progress")
  end

  test "a deploy reports on the build's row", context do
    {:ok, build} = Builds.request_build(context.site, context.environment, [])
    {:ok, ready} = Builds.update(build, %{status: :ready, built_at: DateTime.utc_now()})
    {:ok, view, _html} = live(context.conn, "/admin/config/publishing")
    user = :sys.get_state(view.pid).socket.assigns.current_user

    # The job runs inline: without a strategy it fails at once, with retries
    # left, rather than calling out
    {:ok, _site} = Registry.update_site(context.site, %{deploy_config: %{strategy: nil, target: nil}})
    view |> element("#ssg-build-#{ready.id} button[phx-click=deploy]") |> render_click()

    BrandoAdmin.Work.Registry.sync()
    assert has_element?(view, "#ssg-build-#{ready.id} .work-status[data-status=running]", "Deploying v1")
    BrandoAdmin.Work.finish(user, Brando.Worker.SSGBuild.work_key(ready.id), nil, global: true)
  end

  # Both ask first, in the admin's dialog (assets/src/confirm.js)
  test "deploying and rolling back a build ask before acting", context do
    {:ok, first} = Builds.request_build(context.site, context.environment, [])
    {:ok, archived} = Builds.update(first, %{status: :archived, built_at: DateTime.utc_now()})
    {:ok, second} = Builds.request_build(context.site, context.environment, [])
    {:ok, ready} = Builds.update(second, %{status: :ready, built_at: DateTime.utc_now()})
    {:ok, view, _html} = live(context.conn, "/admin/config/publishing")

    assert has_element?(
             view,
             ~s(#ssg-build-#{ready.id} button[phx-click="deploy"][phx-value-id="#{ready.id}"]) <>
               ~s|[data-confirm="Deploy #{ready.version}?"][data-confirm-ok="Deploy"]:not([data-confirm-destructive])|
           )

    assert has_element?(
             view,
             ~s(#ssg-build-#{archived.id} button[phx-click="rollback"][phx-value-id="#{archived.id}"]) <>
               ~s([data-confirm="Roll back to #{archived.version}?"][data-confirm-ok="Roll back"]) <>
               ":not([data-confirm-destructive])"
           )
  end

  test "does not link a preview on a host where it would answer 404", context do
    admin_host = URI.parse(Brando.endpoint().url()).host

    context.environment
    |> Ecto.Changeset.change(domain: admin_host)
    |> Brando.Repo.update!(prefix: "public")

    Brando.Tenant.Cache.invalidate()

    build =
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, build} = Builds.request_build(context.site, context.environment, creator_id: context.current_user.id)
        build
      end)

    File.mkdir_p!(build.build_path)
    {:ok, _ready} = Builds.update(build, %{status: :ready, built_at: DateTime.utc_now()})

    {:ok, view, _html} = live(context.conn, "/admin/config/publishing")

    refute has_element?(view, ~s(#ssg-build-#{build.id} a[href*="#{admin_host}"]))
    refute has_element?(view, ~s(#ssg-build-#{build.id} a[href*="__ssg_preview__"]))

    context.environment
    |> Ecto.Changeset.change(domain: "https://static-acme.test")
    |> Brando.Repo.update!(prefix: "public")

    Brando.Tenant.Cache.invalidate()
    {:ok, view, _html} = live(context.conn, "/admin/config/publishing")

    refute has_element?(view, ~s(#ssg-build-#{build.id} a[href*="__ssg_preview__"]))
  end

  # A preview opens only on its own site's hosts, which need not be the admin's
  test "links a build's preview on its environment's domain", context do
    {:ok, _environment} = Registry.update_environment(context.environment, %{domain: "static-acme.test"}, actor: :system)

    build =
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, build} = Builds.request_build(context.site, context.environment, creator_id: context.current_user.id)
        build
      end)

    File.mkdir_p!(build.build_path)
    {:ok, _ready} = Builds.update(build, %{status: :ready, built_at: DateTime.utc_now()})

    {:ok, view, _html} = live(context.conn, "/admin/config/publishing")

    assert has_element?(
             view,
             ~s(#ssg-build-#{build.id} a[href="http://static-acme.test/__ssg_preview__/#{build.preview_token}/"])
           )
  end

  test "offers automatic deployment only with a deployment target", context do
    {:ok, view, _html} = live(context.conn, "/admin/config/publishing")
    assert has_element?(view, ~s(#build-static-site input[name="build[auto_deploy]"]))
    assert has_element?(view, ~s(#schedule-static-site input[name="build[auto_deploy]"]))
    assert has_element?(view, ~s(#static-deploy-config input[name="deploy[auto_deploy]"]))

    {:ok, _site} = Registry.update_site(context.site, %{deploy_config: %{strategy: nil, target: nil}})
    {:ok, view, html} = live(context.conn, "/admin/config/publishing")

    assert html =~ "No deployment target configured"
    refute has_element?(view, ~s(input[name="build[auto_deploy]"]))
    refute has_element?(view, ~s(input[name="deploy[auto_deploy]"]))
  end

  test "hides publishing from dynamically delivered sites", context do
    {:ok, _dynamic_site} = Registry.update_site(context.site, %{delivery_mode: :dynamic})

    assert {:error, {:redirect, %{to: "/admin"}}} =
             live(context.conn, "/admin/config/publishing")
  end

  test "updates the static deployment configuration", context do
    {:ok, view, _html} = live(context.conn, "/admin/config/publishing")

    view
    |> form("#static-deploy-config",
      deploy: %{
        strategy: "s3",
        target: "s3://publishing-site/releases",
        cdn_url: "https://static.example.test",
        webhook_url: "https://hooks.example.com/published",
        retention_count: "20",
        auto_deploy: "true"
      }
    )
    |> render_submit()

    updated = Registry.get_site(context.site.id)
    assert updated.deploy_config.strategy == :s3
    assert updated.deploy_config.target == "s3://publishing-site/releases"
    assert updated.deploy_config.auto_deploy
    assert updated.deploy_config.retention_count == 20
  end

  test "an rsync target must be a remote destination", context do
    {:ok, view, _html} = live(context.conn, "/admin/config/publishing")

    for target <- ["/tmp/local-dest", "--log-file=/tmp/marker.log", "u@-oProxyCommand=true:/srv/www"] do
      render_submit(form(view, "#static-deploy-config"), %{"deploy" => %{"strategy" => "rsync", "target" => target}})
      assert Registry.get_site(context.site.id).deploy_config.target == "deploy@example.test:/srv/www"
    end

    render_submit(form(view, "#static-deploy-config"), %{
      "deploy" => %{"strategy" => "rsync", "target" => "web@static.example.test:/srv/site"}
    })

    assert Registry.get_site(context.site.id).deploy_config.target == "web@static.example.test:/srv/site"
  end

  describe "the rsync target's host is looked up on save, not while typing" do
    # Each test's resolver is its own: answers are kept per resolver and host
    defp resolve_with(answers) do
      test = self()

      fn host, family ->
        send(test, {:looked_up, to_string(host), family})

        case Map.get(answers, {to_string(host), family}, {:error, :nxdomain}) do
          :block -> Process.sleep(:infinity)
          answer -> answer
        end
      end
    end

    defp put_resolver(answers, opts \\ []) do
      put_test_env(
        Brando.Sites.DeployConfig,
        [
          resolver: resolve_with(answers),
          rsync_targets: ["deploy@example.test:/srv/www", "web@static.example.test:/srv/site"]
        ] ++ opts
      )
    end

    defp save_target(view, target),
      do: render_submit(form(view, "#static-deploy-config"), %{"deploy" => %{"strategy" => "rsync", "target" => target}})

    defp assert_toast(text) do
      assert_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{payload: message}}
      assert message =~ text
    end

    setup context do
      Brando.endpoint().subscribe("user:#{context.current_user.id}")
      :ok
    end

    test "a change to the form never waits on DNS", context do
      put_resolver(%{{"static.example.test", :inet} => :block, {"static.example.test", :inet6} => :block})
      {:ok, view, _html} = live(context.conn, "/admin/config/publishing")

      {elapsed, _html} =
        :timer.tc(fn ->
          render_change(form(view, "#static-deploy-config"), %{
            "deploy" => %{"strategy" => "rsync", "target" => "web@static.example.test:/srv/site"}
          })
        end)

      assert elapsed < 1_000_000
      refute_received {:looked_up, _host, _family}
      refute_received %Phoenix.Socket.Broadcast{event: "toast"}
    end

    test "a target whose host is this server is refused", context do
      put_resolver(%{{"static.example.test", :inet} => {:ok, [{127, 0, 1, 1}]}})
      {:ok, view, _html} = live(context.conn, "/admin/config/publishing")

      save_target(view, "web@static.example.test:/srv/site")

      assert_toast("must be on another server")
      assert Registry.get_site(context.site.id).deploy_config.target == "deploy@example.test:/srv/www"
    end

    test "a host that cannot be looked up is refused, and is not kept", context do
      put_resolver(%{{"static.example.test", :inet} => {:error, :timeout}})
      {:ok, view, _html} = live(context.conn, "/admin/config/publishing")

      save_target(view, "web@static.example.test:/srv/site")

      assert_toast("could not be looked up")
      assert Registry.get_site(context.site.id).deploy_config.target == "deploy@example.test:/srv/www"

      # Asked again on the next save
      flush_lookups()
      save_target(view, "web@static.example.test:/srv/site")
      assert_received {:looked_up, "static.example.test", :inet}
    end

    test "a lookup that runs out of time is refused", context do
      put_resolver(%{{"static.example.test", :inet6} => :block}, lookup_timeout: 50)
      {:ok, view, _html} = live(context.conn, "/admin/config/publishing")

      save_target(view, "web@static.example.test:/srv/site")

      assert_toast("could not be looked up")
      assert Registry.get_site(context.site.id).deploy_config.target == "deploy@example.test:/srv/www"
    end

    test "saves within a minute reuse the host's answer", context do
      put_resolver(%{{"static.example.test", :inet} => {:ok, [{93, 184, 216, 34}]}})
      {:ok, view, _html} = live(context.conn, "/admin/config/publishing")

      # Refused for another field, so the next save sets the target again
      render_submit(form(view, "#static-deploy-config"), %{
        "deploy" => %{"strategy" => "rsync", "target" => "web@static.example.test:/srv/site", "cdn_url" => "nope"}
      })

      assert Registry.get_site(context.site.id).deploy_config.target == "deploy@example.test:/srv/www"
      save_target(view, "web@static.example.test:/srv/site")

      assert Registry.get_site(context.site.id).deploy_config.target == "web@static.example.test:/srv/site"
      assert_received {:looked_up, "static.example.test", :inet}
      refute_received {:looked_up, "static.example.test", :inet}
    end

    test "a save that keeps the strategy and target does not wait on their host", context do
      put_resolver(%{{"example.test", :inet} => :block, {"example.test", :inet6} => :block})
      {:ok, view, _html} = live(context.conn, "/admin/config/publishing")

      render_submit(form(view, "#static-deploy-config"), %{
        "deploy" => %{"strategy" => "rsync", "target" => "deploy@example.test:/srv/www", "auto_deploy" => "true"}
      })

      assert Registry.get_site(context.site.id).deploy_config.auto_deploy
      refute_received {:looked_up, _host, _family}
    end

    defp flush_lookups do
      receive do
        {:looked_up, _host, _family} -> flush_lookups()
      after
        0 -> :ok
      end
    end
  end

  describe "a site's own allowed deploy targets" do
    setup context do
      Brando.endpoint().subscribe("user:#{context.current_user.id}")
      put_test_env(Brando.Sites.DeployConfig, [])
      :ok
    end

    test "allow a target here, and a refused one says a superuser sets them under Sites", context do
      {:ok, _site} =
        Registry.update_site_deploy_targets(context.site, %{allowed_s3_targets: ["s3://acme-own"]}, :system)

      {:ok, view, _html} = live(context.conn, "/admin/config/publishing")

      render_submit(form(view, "#static-deploy-config"), %{"deploy" => %{"strategy" => "s3", "target" => "s3://other"}})
      assert_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{payload: message}}
      assert message =~ "A superuser sets the site's allowed deploy targets under Sites"
      assert Registry.get_site(context.site.id).deploy_config.strategy == :rsync

      render_submit(form(view, "#static-deploy-config"), %{"deploy" => %{"strategy" => "s3", "target" => "s3://acme-own"}})

      assert Registry.get_site(context.site.id).deploy_config.target == "s3://acme-own"
    end

    test "cannot be changed from here", context do
      {:ok, view, _html} = live(context.conn, "/admin/config/publishing")

      render_submit(form(view, "#static-deploy-config"), %{
        "deploy" => %{
          "strategy" => "s3",
          "target" => "s3://attacker",
          "allowed_s3_targets" => ["s3://attacker"],
          "allowed_rsync_targets" => ["deploy@static.example.test:/srv/"]
        },
        "allowed_s3_targets" => ["s3://attacker"]
      })

      site = Registry.get_site(context.site.id)
      assert site.allowed_s3_targets == []
      assert site.allowed_rsync_targets == []
      assert site.deploy_config.target == "deploy@example.test:/srv/www"
    end
  end

  test "renders nested deployment validation errors without crashing", context do
    {:ok, view, _html} = live(context.conn, "/admin/config/publishing")

    assert render_submit(form(view, "#static-deploy-config"), %{
             "deploy" => %{
               "strategy" => "s3",
               "target" => "not-an-s3-target",
               "webhook_url" => "javascript:alert(1)",
               "retention_count" => "10"
             }
           })

    unchanged = Registry.get_site(context.site.id)
    assert unchanged.deploy_config.strategy == :rsync
    assert unchanged.deploy_config.target == "deploy@example.test:/srv/www"
  end

  test "offers serving the build from this installation, without a target, and shows the build it serves", context do
    {:ok, view, _html} = live(context.conn, "/admin/config/publishing")

    assert has_element?(view, ~s(#static-deploy-config option[value="local"]), "Served by this installation")
    assert has_element?(view, ~s(#static-deploy-config input[name="deploy[target]"]))

    # Choosing it hides the target before it is saved
    render_change(form(view, "#static-deploy-config"), %{"deploy" => %{"strategy" => "local"}})
    refute has_element?(view, ~s(#static-deploy-config input[name="deploy[target]"]))
    assert has_element?(view, "#static-deploy-config .environment-hint", "Until a build is deployed")

    render_submit(form(view, "#static-deploy-config"), %{"deploy" => %{"strategy" => "local", "retention_count" => "10"}})

    site = Registry.get_site(context.site.id)
    assert site.deploy_config.strategy == :local
    assert site.deploy_config.target == nil
    refute has_element?(view, ~s(#static-deploy-config input[name="deploy[target]"]))

    {:ok, build} = Builds.request_build(site, context.environment, [])
    File.mkdir_p!(build.build_path)
    {:ok, ready} = Builds.update(build, %{status: :ready, built_at: DateTime.utc_now()})

    # Deploying needs no target
    assert has_element?(view, "#ssg-build-#{ready.id} button[phx-click=deploy]:not([disabled])")
    {:ok, _deployed} = Brando.SSG.Deploy.deploy(ready)

    {:ok, view, _html} = live(context.conn, "/admin/config/publishing")
    assert has_element?(view, "#static-deploy-config .environment-hint", "answers from v1, the published build")
    assert has_element?(view, "#ssg-build-#{ready.id}", "served by this installation")
    assert has_element?(view, "#ssg-build-#{ready.id} .badge.badge--success .badge-dot")
  end

  test "does not offer serving the build when the installation turns it off", context do
    put_test_env(Brando.Sites.DeployConfig, local_delivery: false, rsync_targets: ["deploy@example.test:/srv/www"])
    {:ok, view, _html} = live(context.conn, "/admin/config/publishing")

    refute has_element?(view, ~s(#static-deploy-config option[value="local"]))
  end

  describe "SSH access" do
    setup context do
      host_key = Brando.SSGSSHFixtures.host_key()
      test_pid = self()

      put_test_env(:ssg_deploy_runner, fn program, args, _opts ->
        send(test_pid, {:ran, program, args})

        case program do
          "ssh-keyscan" -> {"[example.test]:2222 ssh-ed25519 #{host_key}\n", 0}
          "rsync" -> {"", 0}
        end
      end)

      %{known_hosts: Brando.SSG.DeployFiles.path(context.site, :known_hosts)}
    end

    test "save, copy the key, test, accept the host key, and test again", context do
      {:ok, view, _html} = live(context.conn, "/admin/config/publishing")
      # Saved before keys were made: the key is made from here
      refute has_element?(view, "#publishing-public-key")
      assert has_element?(view, "#publishing-ssh button[phx-click=make_deploy_key]:not([data-confirm])")
      refute has_element?(view, "#publishing-ssh button[phx-click=test_connection]")

      view
      |> form("#static-deploy-config", deploy: %{strategy: "rsync", target: "deploy@example.test:/srv/www", port: "2222"})
      |> render_submit()

      site = Registry.get_site(context.site.id)
      assert site.deploy_config.port == 2222
      assert {:ok, public_key} = Brando.SSG.SSH.public_key(site)
      assert has_element?(view, ~s(#publishing-public-key[phx-hook="Brando.CopyText"] input[value="#{public_key}"]))
      refute inspect(:sys.get_state(view.pid).socket.assigns) =~ "PRIVATE KEY"

      view |> element("#publishing-ssh button[phx-click=test_connection]") |> render_click()
      render_async(view)
      assert has_element?(view, "[data-testid=connection-result][data-state=new]")
      refute has_element?(view, "[data-testid=dry-run-ok]")
      assert_received {:ran, "ssh-keyscan", ["-T", "10", "-t", "rsa,ecdsa,ed25519", "-p", "2222", "--", "example.test"]}

      view |> element("#publishing-ssh button[phx-click=accept_host_keys]") |> render_click()
      render_async(view)
      assert File.read!(context.known_hosts) =~ "[example.test]:2222 ssh-ed25519 "
      assert has_element?(view, "[data-testid=connection-result][data-state=accepted]")
      assert has_element?(view, "[data-testid=dry-run-ok]")
      refute has_element?(view, "#publishing-ssh button[phx-click=accept_host_keys]")
      assert_received {:ran, "rsync", ["-e", "ssh -i " <> _, "-an" | _]}
    end

    test "the port shows for rsync alone", context do
      {:ok, view, _html} = live(context.conn, "/admin/config/publishing")
      assert has_element?(view, ~s(#static-deploy-config input[name="deploy[port]"][value="22"]))

      render_change(view, "change_deploy_config", %{"deploy" => %{"strategy" => "s3"}})
      refute has_element?(view, ~s(#static-deploy-config input[name="deploy[port]"]))
    end

    test "rotating asks first, and says the old key stays on the host", context do
      Brando.SSG.SSH.ensure_key(context.site, context.current_user)
      {:ok, view, _html} = live(context.conn, "/admin/config/publishing")

      assert view
             |> element("#publishing-ssh button[phx-click=rotate_deploy_key][data-confirm]")
             |> render() =~ "authorized_keys"
    end

    test "making a key keeps one made since the screen opened", context do
      {:ok, view, _html} = live(context.conn, "/admin/config/publishing")
      # Another admin makes the key, and installs it on the host
      {:ok, made} = Brando.SSG.SSH.ensure_key(context.site, context.current_user)

      view |> element("#publishing-ssh button[phx-click=make_deploy_key]") |> render_click()
      assert {:ok, ^made} = Brando.SSG.SSH.public_key(context.site)
      assert has_element?(view, ~s(#publishing-public-key input[value="#{made}"]))
    end

    test "a key that cannot be written says so, on rotate and on save", context do
      Brando.endpoint().subscribe("user:#{context.current_user.id}")
      # No key to read, and nowhere to write one: the deploy directory is a link to nothing
      dir = Brando.SSG.DeployFiles.dir(context.site)
      File.mkdir_p!(Path.dirname(dir))
      File.ln_s!(Path.join(Path.dirname(dir), "missing/deploy"), dir)

      {:ok, view, _html} = live(context.conn, "/admin/config/publishing")

      render_submit(form(view, "#static-deploy-config"), %{
        "deploy" => %{"strategy" => "rsync", "target" => "deploy@example.test:/srv/www"}
      })

      assert_toast_said("could not be written")

      # A key that cannot be read, and a rotation that cannot replace it
      File.rm!(dir)
      File.mkdir_p!(Path.join(Brando.SSG.DeployFiles.path(context.site, :key), "taken"))
      {:ok, view, _html} = live(context.conn, "/admin/config/publishing")
      view |> element("#publishing-ssh button[phx-click=rotate_deploy_key]") |> render_click()
      assert_toast_said("could not be written")
    end

    # The panel says the key cannot be read, and to rotate it: nothing was written
    test "a save beside a key that cannot be read reports no failed write", context do
      Brando.endpoint().subscribe("user:#{context.current_user.id}")
      {:ok, _site} = Registry.update_site(context.site, %{deploy_config: %{port: 22}})
      key = Brando.SSG.DeployFiles.path(context.site, :key)
      File.mkdir_p!(Path.dirname(key))
      File.write!(key, "not a key")

      {:ok, view, _html} = live(context.conn, "/admin/config/publishing")

      render_submit(form(view, "#static-deploy-config"), %{
        "deploy" => %{"strategy" => "rsync", "target" => "deploy@example.test:/srv/www"}
      })

      assert render(view) =~ "publishing-ssh"
      refute_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{level: :error}}, 300
    end

    test "an accept over keys accepted since the test asks for a new test", context do
      Brando.endpoint().subscribe("user:#{context.current_user.id}")
      {:ok, _site} = Registry.update_site(context.site, %{deploy_config: %{port: 2222}})
      {:ok, _key} = Brando.SSG.SSH.ensure_key(context.site, context.current_user)
      {:ok, view, _html} = live(context.conn, "/admin/config/publishing")
      view |> element("#publishing-ssh button[phx-click=test_connection]") |> render_click()
      render_async(view)

      # Another admin accepts the host's keys meanwhile
      File.write!(context.known_hosts, "[example.test]:2222 ssh-ed25519 #{Brando.SSGSSHFixtures.other_host_key()}\n")

      view |> element("#publishing-ssh button[phx-click=accept_host_keys]") |> render_click()
      assert_toast_said("Test the connection again")
    end

    # Among the toasts sent, which arrive in no set order
    defp assert_toast_said(text) do
      receive do
        %Phoenix.Socket.Broadcast{event: "toast", payload: %{payload: message}} ->
          if message =~ text, do: :ok, else: assert_toast_said(text)
      after
        1_000 -> flunk("No toast said #{inspect(text)}")
      end
    end

    test "a user who may open the screen but not publish sees no key and can do nothing", context do
      editor = Brando.Factory.insert(:random_user, role: :editor, config: %Brando.Users.UserConfig{})
      {:ok, _} = Brando.Tenant.Access.grant(editor, context.site, :editor)
      Brando.SSG.SSH.ensure_key(context.site, context.current_user)
      conn = context.conn |> recycle() |> log_in_user(editor)
      {:ok, view, html} = live(conn, "/admin/config/publishing")

      refute html =~ "ssh-ed25519"
      refute has_element?(view, "#publishing-ssh")
      {:ok, public_key} = Brando.SSG.SSH.public_key(context.site)

      for event <- ~w(make_deploy_key rotate_deploy_key test_connection accept_host_keys) do
        render_click(view, event, %{})
        render_async(view)
      end

      assert {:ok, ^public_key} = Brando.SSG.SSH.public_key(context.site)
      refute File.exists?(context.known_hosts)
      refute_received {:ran, _, _}
      refute render(view) =~ "ssh-ed25519"
    end
  end

  # The host may take its time: what changes meanwhile makes the answer old
  describe "a connection test's answer" do
    setup context do
      host_key = Brando.SSGSSHFixtures.host_key()
      test_pid = self()

      put_test_env(:ssg_deploy_runner, fn
        "ssh-keyscan", _args, _opts ->
          send(test_pid, {:scanning, self()})

          receive do
            :answer -> {"[example.test]:2222 ssh-ed25519 #{host_key}\n", 0}
          end

        "rsync", _args, _opts ->
          {"", 0}
      end)

      {:ok, site} = Registry.update_site(context.site, %{deploy_config: %{port: 2222}})
      {:ok, _key} = Brando.SSG.SSH.ensure_key(site, context.current_user)
      Brando.SSG.DeployFiles.write(site, :known_hosts, "[example.test]:2222 ssh-ed25519 #{host_key}\n")
      {:ok, view, _html} = live(context.conn, "/admin/config/publishing")
      %{view: view}
    end

    defp start_test(view) do
      view |> element("#publishing-ssh button[phx-click=test_connection]") |> render_click()
      assert_receive {:scanning, scanner}
      scanner
    end

    defp answer(view, scanner) do
      send(scanner, :answer)
      render_async(view)
    end

    test "shows when nothing changed", %{view: view} do
      answer(view, start_test(view))
      assert has_element?(view, "[data-testid=dry-run-ok]")
    end

    test "is dropped after a save here", %{view: view} do
      scanner = start_test(view)

      render_submit(form(view, "#static-deploy-config"), %{
        "deploy" => %{"strategy" => "rsync", "target" => "deploy@example.test:/srv/www", "port" => "22"}
      })

      answer(view, scanner)
      refute has_element?(view, "[data-testid=connection-result]")
    end

    test "is dropped after a save elsewhere", %{view: view} = context do
      scanner = start_test(view)
      {:ok, _site} = Registry.update_site(Registry.get_site(context.site.id), %{deploy_config: %{port: 22}})

      answer(view, scanner)
      refute has_element?(view, "[data-testid=connection-result]")
    end

    test "is dropped after a rotation", %{view: view} do
      scanner = start_test(view)
      view |> element("#publishing-ssh button[phx-click=rotate_deploy_key]") |> render_click()

      answer(view, scanner)
      refute has_element?(view, "[data-testid=connection-result]")
    end
  end

  describe "SSH access takes a recent confirmation" do
    setup %{conn: conn} = context do
      token = get_session(conn, :user_token)
      at = NaiveDateTime.add(NaiveDateTime.utc_now(), -30 * 60, :second)

      Brando.Repo.update_all(
        from(t in Brando.Users.UserToken, where: t.token == ^token),
        set: [confirmed_at: at]
      )

      Brando.SSG.SSH.ensure_key(context.site, context.current_user)
      :ok
    end

    test "to rotate the key", context do
      {:ok, before} = Brando.SSG.SSH.public_key(context.site)
      {:ok, view, _html} = live(context.conn, "/admin/config/publishing")

      assert render_click(view, "rotate_deploy_key", %{}) =~ "reauth-modal"
      assert {:ok, ^before} = Brando.SSG.SSH.public_key(context.site)

      view |> form("#reauth-form", reauth: %{proof: "admin"}) |> render_submit()
      refute Brando.SSG.SSH.public_key(context.site) == {:ok, before}
    end

    test "to accept a host key", context do
      {:ok, view, _html} = live(context.conn, "/admin/config/publishing")
      assert render_click(view, "accept_host_keys", %{}) =~ "reauth-modal"
    end
  end
end

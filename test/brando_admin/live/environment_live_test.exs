defmodule BrandoAdmin.Sites.EnvironmentLiveTest do
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.Groups
  alias Brando.Authorization.Migration
  alias Brando.Authorization.Scope
  alias Brando.Environments
  alias Brando.Environments.OperationLog
  alias Brando.Environments.Schema
  alias Brando.Tenant
  alias Brando.Tenant.Access
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry

  defmodule Migrator do
    @behaviour Brando.Environments.Migrator

    @impl true
    def migrate(_site, _environment), do: {:ok, [20_260_816_000_001]}
  end

  defmodule SchemaCloner do
    @behaviour Brando.Environments.SchemaCloner

    @impl true
    def clone_schema(_source_prefix, target_prefix), do: Schema.create(target_prefix)
  end

  defmodule StructureCloner do
    @behaviour Brando.Environments.StructureCloner

    @impl true
    def clone_structure(_source_prefix, _target_prefix), do: :ok
  end

  setup do
    put_test_env(:tenancy_mode, :multi)
    put_test_env(:tenant_migrator, Migrator)
    put_test_env(:tenant_structure_cloner, StructureCloner)
    put_test_env(:environment_schema_cloner, SchemaCloner)
    Cache.clear()
    Tenant.put_prefix(nil)

    on_exit(fn ->
      Cache.clear()
      Tenant.put_prefix(nil)
    end)

    {:ok, site} =
      Registry.create_site(%{
        name: "Acme",
        key: "acme-environment-live",
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :dynamic
      })

    {:ok, production} =
      Environments.create_environment(site, %{
        name: "Production",
        key: "production",
        live: true
      })

    %{site: site, production: production}
  end

  # Audit F02: which site answers on a host is the installation's decision.
  describe "binding a host" do
    setup %{site: site} do
      {:ok, other_site} =
        Registry.create_site(%{
          name: "Other",
          key: "other-environment-live",
          languages: ["en"],
          default_language: "en",
          status: :active,
          delivery_mode: :dynamic
        })

      {:ok, other} =
        Environments.create_environment(
          other_site,
          %{name: "Production", key: "production", live: true, domain: "www.other.test"},
          creator: :system
        )

      {:ok, staging} =
        Environments.create_environment(
          site,
          %{name: "Staging", key: "staging", domain: "staging.acme.test"},
          creator: :system
        )

      %{other: other, staging: staging}
    end

    defp site_admin_conn(site) do
      admin = Factory.insert(:random_user, role: :editor, config: %Brando.Users.UserConfig{})
      {:ok, _assignment} = Access.grant(admin, site, :admin)
      log_in_user(build_conn(), admin)
    end

    defp group_admin_conn(site, production, owner) do
      {:ok, _} = Migration.run()
      admin = Factory.insert(:random_user, role: :editor, config: %Brando.Users.UserConfig{})
      owner_scope = Scope.site(owner, site, production)

      {:ok, group} =
        Groups.create(owner_scope, %{name: "Site admins"}, [
          "brando.admin.access",
          "brando.environments.read",
          "brando.environments.create",
          "brando.environments.update"
        ])

      {:ok, :ok} = Groups.add_member(owner_scope, group.id, admin.id)
      log_in_user(build_conn(), admin)
    end

    defp submit_domain(view, environment, domain),
      do: render_submit(view, "update_domain", %{"environment_id" => environment.id, "domain" => domain})

    defp submit_new(view, key, domain),
      do:
        render_submit(view, "create_environment", %{"environment" => %{"name" => key, "key" => key, "domain" => domain}})

    defp assert_refused(view, site, environment) do
      for host <- ["cms.free.test", "localhost", "www.other.test.", ""] do
        submit_domain(view, environment, host)
        assert Registry.get_environment(environment.id).domain == environment.domain, inspect(host)
      end

      submit_new(view, "claimed", "cms.free.test")
      refute Registry.get_environment_by_key(site, "claimed")
      refute Cache.get_env_by_domain("cms.free.test")
    end

    test "a per-site admin in legacy mode cannot bind, move or clear one", %{site: site, staging: staging} do
      {:ok, view, html} = live(site_admin_conn(site), "/admin/config/environments")

      assert_refused(view, site, staging)
      assert html =~ ~s(aria-label="Domain for Staging")
      assert has_element?(view, ~s(#environment-#{staging.id} input[name="domain"][disabled]))
      refute has_element?(view, ~s(#create-environment-form input[name="environment[domain]"]))
    end

    test "a site admin in groups mode cannot either", %{
      site: site,
      production: production,
      staging: staging,
      current_user: owner
    } do
      put_test_env(:authorization_mode, :groups)
      {:ok, view, _html} = live(group_admin_conn(site, production, owner), "/admin/config/environments")

      assert_refused(view, site, staging)
      assert has_element?(view, ~s(#environment-#{staging.id} input[name="domain"][disabled]))
    end

    test "an admin in single-site mode cannot either", %{conn: _conn, site: site, staging: staging} do
      put_test_env(:tenancy_mode, :single)
      put_test_env(:site_key, site.key)
      Cache.invalidate()
      admin = Factory.insert(:random_user, role: :admin, config: %Brando.Users.UserConfig{})
      {:ok, view, _html} = live(log_in_user(build_conn(), admin), "/admin/config/environments")

      assert_refused(view, site, staging)
    end

    test "a per-site admin still creates an environment without a host", %{site: site} do
      {:ok, view, _html} = live(site_admin_conn(site), "/admin/config/environments")

      submit_new(view, "no-host", "")

      assert %{domain: nil} = Registry.get_environment_by_key(site, "no-host")
    end

    test "a superuser binds, moves and clears one, in both modes", %{
      conn: conn,
      site: site,
      staging: staging
    } do
      for {mode, host} <- [legacy: "one.acme.test", groups: "two.acme.test"] do
        put_test_env(:authorization_mode, mode)
        if mode == :groups, do: {:ok, _} = Migration.run()
        {:ok, view, _html} = live(conn, "/admin/config/environments")

        submit_domain(view, staging, "  #{String.upcase(host)} ")
        assert Registry.get_environment(staging.id).domain == host
        assert {%{id: site_id}, %{id: staging_id}} = Cache.get_env_by_domain(host)
        assert {site_id, staging_id} == {site.id, staging.id}

        submit_domain(view, staging, "")
        assert Registry.get_environment(staging.id).domain == nil
        refute Cache.get_env_by_domain(host)
      end
    end

    test "a superuser in groups mode is the Superuser group's, not the role's", %{
      site: site,
      staging: staging,
      production: production,
      current_user: owner
    } do
      put_test_env(:authorization_mode, :groups)
      {:ok, _} = Migration.run()
      # A superuser by legacy role, whose authority here is a site group only
      role_only = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
      owner_scope = Scope.site(owner, site, production)

      {:ok, group} =
        Groups.create(owner_scope, %{name: "Site admins"}, [
          "brando.admin.access",
          "brando.environments.read",
          "brando.environments.update"
        ])

      {:ok, :ok} = Groups.add_member(owner_scope, group.id, role_only.id)

      installation = Scope.installation(owner)
      {:ok, installation_groups} = Groups.list(installation)

      for %{id: id} <- installation_groups, id != group.id do
        Groups.remove_member(installation, id, role_only.id)
      end

      {:ok, view, _html} = live(log_in_user(build_conn(), role_only), "/admin/config/environments")

      submit_domain(view, staging, "cms.free.test")

      assert Registry.get_environment(staging.id).domain == "staging.acme.test"
    end

    test "a superuser cannot bind what is no host, the installation's or another site's", %{
      conn: conn,
      staging: staging
    } do
      {:ok, view, _html} = live(conn, "/admin/config/environments")

      for host <- ["localhost", "https://x.test", "x.test.", "www.other.test"] do
        submit_domain(view, staging, host)
        assert Registry.get_environment(staging.id).domain == "staging.acme.test", inspect(host)
      end
    end

    test "setting a live environment moves its stored host, however it is spelled", %{
      site: site,
      production: production,
      staging: staging
    } do
      for stored <- ["Staging.Acme.TEST", "staging.acme.test.", "https://staging.acme.test"] do
        # Back to production live with no domain, staging holding the stored one
        for {id, set} <- [
              {production.id, [domain: nil]},
              {staging.id, [domain: stored, live: false]},
              {production.id, [live: true]}
            ] do
          Brando.Repo.update_all(from(e in Brando.Environments.Environment, where: e.id == ^id), [set: set],
            prefix: "public"
          )
        end

        assert {:ok, %{live: true, domain: nil}} =
                 Environments.set_live(Registry.get_environment(staging.id), creator: :system)

        assert Registry.get_environment(production.id).domain == stored
        assert Cache.get_live_env(site.key).id == staging.id
      end
    end

    test "a per-site admin sets an environment with a stored host live", %{
      site: site,
      production: production,
      staging: staging
    } do
      {:ok, view, _html} = live(site_admin_conn(site), "/admin/config/environments")

      Oban.Testing.with_testing_mode(:manual, fn ->
        render_submit(view, "schedule_set_live", %{
          "operation" => %{
            "environment_id" => staging.id,
            "scheduled_at" =>
              DateTime.utc_now()
              |> DateTime.add(7200)
              |> DateTime.shift_zone!(Brando.timezone())
              |> Calendar.strftime("%Y-%m-%dT%H:%M")
          }
        })
      end)

      assert has_element?(view, "#environment-#{staging.id}")

      assert {:ok, %{live: true, domain: nil}} =
               Environments.set_live(Registry.get_environment(staging.id), creator: :system)

      assert Registry.get_environment(production.id).domain == "staging.acme.test"
    end

    # A live switch moves hosts without a superuser, so a superuser's screen
    # can show a host an environment no longer holds
    test "a domain submitted from a stale screen leaves the moved hosts alone", %{
      conn: conn,
      production: production,
      staging: staging
    } do
      {:ok, _production} = Registry.update_environment(production, %{domain: "www.acme.test"}, actor: :system)
      {:ok, view, _html} = live(conn, "/admin/config/environments")

      # The hosts swap underneath, with nothing telling the screen
      for {id, domain} <- [{production.id, nil}, {staging.id, "www.acme.test"}, {production.id, "staging.acme.test"}] do
        Brando.Repo.update_all(
          from(e in Brando.Environments.Environment, where: e.id == ^id),
          [set: [domain: domain]],
          prefix: "public"
        )
      end

      # Clearing the www.acme.test the screen shows for production
      submit_domain(view, production, "")

      assert Registry.get_environment(production.id).domain == "staging.acme.test"
      assert Registry.get_environment(staging.id).domain == "www.acme.test"
      # The screen now shows the hosts where they are
      assert has_element?(view, ~s(#environment-#{production.id} input[name="domain"][value="staging.acme.test"]))

      submit_domain(view, production, "")
      assert Registry.get_environment(production.id).domain == nil
    end
  end

  test "copying into the live environment has to be ticked", %{conn: conn, site: site, production: production} do
    {:ok, preview} =
      Environments.create_environment(site, %{name: "Preview", key: "preview-copy-live", domain: "p.example.com"},
        creator: :system
      )

    {:ok, view, _html} = live(conn, "/admin/config/environments")

    copies = fn ->
      Brando.Repo.all(from(l in OperationLog, where: l.target_environment_id == ^production.id and l.operation == :copy),
        prefix: "public"
      )
    end

    view
    |> form("#copy-environment-form", operation: %{source_id: preview.id, target_id: production.id})
    |> render_submit()

    assert copies.() == []

    view
    |> form("#copy-environment-form", operation: %{source_id: preview.id, target_id: production.id, replace_live: "true"})
    |> render_submit()

    assert [%OperationLog{operation: :copy}] = copies.()
  end

  test "creates an environment and exposes a queued copy that can be cancelled", %{
    conn: conn,
    site: site,
    production: production
  } do
    {:ok, view, html} = live(conn, "/admin/config/environments")

    assert html =~ "Environments"
    assert has_element?(view, "#environment-#{production.id}", "Production")

    view
    |> form("#create-environment-form",
      environment: %{
        name: "Spring Redesign",
        key: "spring-redesign",
        domain: "spring.example.com"
      }
    )
    |> render_submit()

    preview = Registry.get_environment_by_key(site, "spring-redesign")

    assert preview
    assert has_element?(view, "#environment-#{preview.id}", "Spring Redesign")

    view
    |> form("#copy-environment-form",
      operation: %{
        source_id: production.id,
        target_id: preview.id,
        note: "Release rehearsal"
      }
    )
    |> render_submit()

    assert %OperationLog{note: "Release rehearsal"} =
             Brando.Repo.get_by(
               OperationLog,
               [site_id: site.id, operation: :copy],
               prefix: "public"
             )

    scheduled_at = DateTime.add(DateTime.utc_now(), 3_600, :second)

    job =
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, job} =
                 Environments.schedule_copy(production, preview, scheduled_at, note: "Release rehearsal")

        job
      end)

    view
    |> element("button", "Refresh")
    |> render_click()

    assert [listed_job] = Environments.list_scheduled_operations(site)
    assert listed_job.id == job.id
    assert has_element?(view, "#environment-job-#{job.id}", "Copy Production → Spring Redesign")
    assert has_element?(view, "#environment-job-#{job.id} .environment-state", "Scheduled")

    view
    |> element("#environment-job-#{job.id} button", "Cancel")
    |> render_click()

    # The test suite runs Oban's inline engine, whose cancel callback is a
    # deliberate no-op. Exercise the persistence side in manual mode, then
    # verify that the management screen removes the cancelled operation.
    assert :ok =
             Oban.Testing.with_testing_mode(:manual, fn ->
               Environments.cancel_scheduled_operation(site, job.id)
             end)

    view
    |> element("button", "Refresh")
    |> render_click()

    assert Environments.list_scheduled_operations(site) == []
    refute has_element?(view, "#environment-job-#{job.id}")
  end

  # Scheduled by someone who may no longer promote the site's environments:
  # the open screen's operation log shows it cancelled, and why
  test "shows a scheduled operation cancelled when it was due", %{conn: conn, site: site} do
    {:ok, preview} = Environments.create_environment(site, %{name: "Preview", key: "preview-cancelled"})
    scheduler = Brando.Factory.insert(:random_user, role: :user, name: "Sam Scheduler")

    {:ok, view, _html} = live(conn, "/admin/config/environments")

    job =
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, job} =
          %{site_id: site.id, environment_id: preview.id, creator_id: scheduler.id}
          |> Brando.Worker.EnvironmentSetLive.new()
          |> Oban.insert()

        assert %{cancelled: 1} = Oban.drain_queue(queue: :environment_operations)
        job
      end)

    refute has_element?(view, "#environment-job-#{job.id}")

    [log] =
      Brando.Repo.all(from(l in OperationLog, where: l.site_id == ^site.id and not is_nil(l.cancelled_reason)),
        prefix: "public"
      )

    row = "#environment-log-#{log.id}"
    assert has_element?(view, "#{row} .badge--error")
    assert has_element?(view, "#{row} .environment-log__reason", "Sam Scheduler")
    assert has_element?(view, "#{row} code", "preview-cancelled")
  end

  defmodule RaisingSchemaCloner do
    @behaviour Brando.Environments.SchemaCloner

    @impl true
    def clone_schema(_source_prefix, target_prefix) do
      :ok = Schema.create(target_prefix)
      raise "the clone broke halfway"
    end
  end

  @tag :capture_log
  test "a restore that fails says so, and leaves nothing behind", %{
    conn: conn,
    site: site,
    production: production,
    current_user: user
  } do
    {:ok, preview} = Environments.create_environment(site, %{name: "Preview", key: "preview-restore"})
    assert {:ok, _} = Environments.copy_environment(production, preview)
    put_test_env(:environment_schema_cloner, RaisingSchemaCloner)
    Brando.endpoint().subscribe("user:#{user.id}")

    {:ok, view, _html} = live(conn, "/admin/config/environments")

    view
    |> element("button[phx-click=rollback]:not([phx-value-schema])")
    |> render_click()

    # The restore runs in its own task, which reports back to the page
    assert_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{level: :error}}, 5_000
    assert render(view)
    refute Enum.any?(Registry.list_environments(site), &String.starts_with?(&1.key, "rollback"))

    assert BrandoIntegration.Repo.query!(
             "SELECT count(*) FROM pg_namespace WHERE nspname LIKE 'tenant_acme-environment-live_rollback%'"
           ).rows ==
             [[0]]
  end

  # The log names each operation, not its atom (`set_live`, `copy`), and an
  # archive the operation it was saved before
  test "the operation log and the archives name their operations", %{conn: conn, site: site, production: production} do
    {:ok, preview} = Environments.create_environment(site, %{name: "Preview", key: "preview-log"})
    assert {:ok, _} = Environments.copy_environment(production, preview)

    {:ok, view, _html} = live(conn, "/admin/config/environments")

    assert has_element?(view, ".environment-log__operation", "Created")
    assert has_element?(view, ".environment-log__operation", "Copied")
    refute has_element?(view, ".environment-log__operation", ~r/^\s*(copy|create)\s*$/)
    assert has_element?(view, ".environment-archive__meta span", "Saved before a copy")
  end

  test "editors cannot invoke environment lifecycle events", %{site: site} do
    editor =
      Brando.Factory.insert(:random_user,
        role: :editor,
        config: %Brando.Users.UserConfig{}
      )

    assert {:ok, _assignment} = Access.grant(editor, site, :editor)

    conn = log_in_user(Phoenix.ConnTest.build_conn(), editor)
    {:ok, view, _html} = live(conn, "/admin/config/environments")

    assert has_element?(view, "#create-environment-form button[disabled]")

    view
    |> form("#create-environment-form",
      environment: %{name: "Forbidden", key: "forbidden"}
    )
    |> render_submit()

    refute Registry.get_environment_by_key(site, "forbidden")
  end

  describe "changing the host an environment answers on takes a recent confirmation" do
    setup %{conn: conn} do
      token = get_session(conn, :user_token)
      at = NaiveDateTime.add(NaiveDateTime.utc_now(), -30 * 60, :second)
      Repo.update_all(from(t in Brando.Users.UserToken, where: t.token == ^token), set: [confirmed_at: at])
      :ok
    end

    for mode <- [:legacy, :groups] do
      test "assigning a domain waits for the password, #{mode} mode", %{conn: conn, site: site} do
        {:ok, staging} = Environments.create_environment(site, %{name: "Staging", key: "staging", live: false})
        groups_mode(unquote(mode))
        {:ok, view, _html} = live(conn, "/admin/config/environments")

        html = render_submit(view, "update_domain", %{"environment_id" => staging.id, "domain" => "moved.acme.test"})
        assert html =~ "reauth-modal"
        assert Registry.get_environment(staging.id).domain == staging.domain

        view |> form("#reauth-form", reauth: %{proof: "admin"}) |> render_submit()
        assert Registry.get_environment(staging.id).domain == "moved.acme.test"
      end

      test "creating an environment on a domain waits for the password, #{mode} mode", %{conn: conn, site: site} do
        groups_mode(unquote(mode))
        {:ok, view, _html} = live(conn, "/admin/config/environments")
        attrs = %{"name" => "Claimed", "key" => "claimed", "domain" => "claimed.acme.test"}

        html = render_submit(view, "create_environment", %{"environment" => attrs})
        assert html =~ "reauth-modal"
        refute Registry.get_environment_by_key(site, "claimed")
        refute Cache.get_env_by_domain("claimed.acme.test")

        view |> form("#reauth-form", reauth: %{proof: "admin"}) |> render_submit()
        assert %{domain: "claimed.acme.test"} = Registry.get_environment_by_key(site, "claimed")
      end
    end

    # Answering proves who you are: it takes no grant of its own, or a holder of
    # the create grant alone could never get past the prompt.
    test "the prompt can be answered with the create grant alone", %{
      site: site,
      production: production,
      current_user: owner
    } do
      put_test_env(:authorization_mode, :groups)
      {:ok, _} = Migration.run()
      creator = Factory.insert(:random_user, role: :editor, config: %Brando.Users.UserConfig{})
      owner_scope = Scope.site(owner, site, production)

      {:ok, group} =
        Groups.create(owner_scope, %{name: "Environment creators"}, [
          "brando.admin.access",
          "brando.environments.read",
          "brando.environments.create"
        ])

      {:ok, :ok} = Groups.add_member(owner_scope, group.id, creator.id)
      conn = log_in_user(build_conn(), creator)
      token = get_session(conn, :user_token)
      at = NaiveDateTime.add(NaiveDateTime.utc_now(), -30 * 60, :second)
      Repo.update_all(from(t in Brando.Users.UserToken, where: t.token == ^token), set: [confirmed_at: at])
      {:ok, view, _html} = live(conn, "/admin/config/environments")

      html = render_submit(view, "create_environment", %{"environment" => %{"name" => "New", "key" => "new-one"}})
      assert html =~ "reauth-modal"

      view |> form("#reauth-form", reauth: %{proof: "admin"}) |> render_submit()
      assert Registry.get_environment_by_key(site, "new-one")
    end

    defp groups_mode(:legacy), do: :ok

    defp groups_mode(:groups) do
      put_test_env(:authorization_mode, :groups)
      {:ok, _} = Migration.run()
    end
  end
end

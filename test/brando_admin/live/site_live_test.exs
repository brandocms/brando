defmodule BrandoAdmin.Sites.SiteLiveTest do
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Environments.Schema
  alias Brando.Tenant.Access
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

  defmodule Seeder do
    @behaviour Brando.Tenant.Seeder

    @impl true
    def seed(_site, _environment, _creator), do: :ok
  end

  setup do
    root = Path.join(System.tmp_dir!(), "brando-site-live-#{System.unique_integer([:positive])}")

    put_test_env(:tenancy_mode, :multi)
    put_test_env(:tenant_migrator, Migrator)
    put_test_env(:tenant_structure_cloner, StructureCloner)
    put_test_env(:environment_schema_cloner, SchemaCloner)
    put_test_env(:tenant_seeder, Seeder)
    put_test_env(:media_path, Path.join(root, "media"))
    put_test_env(:sites_path, Path.join(root, "sites"))
    Brando.Tenant.Cache.clear()

    on_exit(fn ->
      File.rm_rf(root)
      Brando.Tenant.put_prefix(nil)
      Brando.Tenant.Cache.clear()
    end)

    {:ok, site} =
      Registry.create_site(%{
        name: "Existing Site",
        key: "existing-site-dashboard",
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :dynamic
      })

    {:ok, _environment} =
      Registry.create_environment(
        site,
        %{
          name: "Production",
          key: "production",
          live: true,
          domain: "existing.dashboard.test"
        },
        actor: :system
      )

    editor =
      Brando.Factory.insert(:random_user,
        role: :editor,
        config: %Brando.Users.UserConfig{}
      )

    %{editor: editor, site: Registry.get_site(site.id)}
  end

  test "superusers provision sites and manage per-site assignments", %{conn: conn, editor: editor} do
    {:ok, view, html} = live(conn, "/admin/sites")

    assert html =~ "Existing Site"

    view
    |> form("#create-site-form",
      site: %{
        name: "New Client",
        key: "new-client-dashboard",
        languages: "en,no",
        default_language: "en",
        delivery_mode: "dynamic"
      }
    )
    |> render_submit()

    created = Registry.get_site_by_key("new-client-dashboard")
    assert created
    assert Enum.map(created.environments, & &1.key) |> Enum.sort() == ["production", "staging"]
    assert has_element?(view, "#site-#{created.id}", "New Client")

    view
    |> form("#grant-site-#{created.id}",
      assignment: %{site_id: created.id, user_id: editor.id, role: "admin"}
    )
    |> render_submit()

    assert Access.role_for(editor, created) == :admin
    assert has_element?(view, "#site-#{created.id}", editor.email)

    view
    |> element("#site-#{created.id} button[phx-click=revoke][phx-value-user-id=\"#{editor.id}\"]")
    |> render_click()

    refute Access.can_access?(editor, created)
  end

  # The installation scope the screen runs under grants no content in a
  # site: the default seeder writes as the system
  test "in groups mode, a site created here gets the default content", %{conn: conn} do
    prefixes = ~w(tenant_seeded-client_production tenant_seeded-client_staging)
    on_exit(fn -> Brando.TenantCaches.clear(prefixes) end)

    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenant_seeder, Brando.Tenant.Seeder)
    put_test_env(:tenant_structure_cloner, Brando.TenantCloners)
    put_test_env(:environment_schema_cloner, Brando.TenantCloners)
    {:ok, _} = Brando.Authorization.Migration.run()

    {:ok, view, _html} = live(conn, "/admin/sites")

    view
    |> form("#create-site-form",
      site: %{name: "Seeded Client", key: "seeded-client", languages: "en", default_language: "en"}
    )
    |> render_submit()

    assert %{} = site = Registry.get_site_by_key("seeded-client")

    for environment <- site.environments do
      Brando.Tenant.with_prefix(Brando.Tenant.prefix(site, environment), fn ->
        assert Brando.Repo.get_by(Brando.Navigation.Menu, key: "main", language: :en)
        assert Brando.Repo.get_by(Brando.Pages.Page, uri: "index", language: :en)
      end)
    end
  end

  test "site lifecycle actions immediately update status", %{conn: conn, site: site} do
    {:ok, view, _html} = live(conn, "/admin/sites")

    view
    |> element("#site-#{site.id} button", "Suspend")
    |> render_click()

    assert Registry.get_site(site.id).status == :suspended
    assert has_element?(view, "#site-#{site.id} .badge", "Suspended")

    view
    |> element("#site-#{site.id} button", "Archive")
    |> render_click()

    archived = Registry.get_site(site.id)
    assert archived.status == :archived
    assert archived.archived_at

    view
    |> element("#site-#{site.id} button", "Permanently delete")
    |> render_click()

    assert Registry.get_site(site.id)
  end

  describe "provider library group" do
    test "a superuser puts sites in one group, and takes one out", %{conn: conn, site: site} do
      {:ok, other} =
        Registry.create_site(%{
          name: "Sister Site",
          key: "sister-site-dashboard",
          languages: ["en"],
          default_language: "en",
          status: :active,
          delivery_mode: :dynamic
        })

      {:ok, view, _html} = live(conn, "/admin/sites")

      for {id, group} <- [{site.id, "agency"}, {other.id, " agency "}] do
        view
        |> form("#library-group-site-#{id}", site: %{id: id, provider_library_group: group})
        |> render_submit()
      end

      assert Registry.get_site(site.id).provider_library_group == "agency"
      assert Registry.get_site(other.id).provider_library_group == "agency"
      assert has_element?(view, "#library-group-site-#{site.id}", "Sister Site")

      view
      |> form("#library-group-site-#{other.id}", site: %{id: other.id, provider_library_group: ""})
      |> render_submit()

      assert Registry.get_site(other.id).provider_library_group == nil
      refute has_element?(view, "#library-group-site-#{site.id}", "Sister Site")
    end

    test "a malformed key is refused", %{conn: conn, site: site} do
      {:ok, view, _html} = live(conn, "/admin/sites")

      view
      |> form("#library-group-site-#{site.id}", site: %{id: site.id, provider_library_group: "Two Words"})
      |> render_submit()

      assert Registry.get_site(site.id).provider_library_group == nil
    end

    test "in groups mode, an installation superuser sets it", %{conn: conn, site: site} do
      put_test_env(:authorization_mode, :groups)
      {:ok, _} = Brando.Authorization.Migration.run()

      {:ok, view, _html} = live(conn, "/admin/sites")

      view
      |> form("#library-group-site-#{site.id}", site: %{id: site.id, provider_library_group: "agency"})
      |> render_submit()

      assert Registry.get_site(site.id).provider_library_group == "agency"
    end
  end

  describe "a site's languages" do
    setup %{current_user: user} do
      prefixes = ~w(tenant_acme_production tenant_acme_staging)
      on_exit(fn -> Brando.TenantCaches.clear(prefixes) end)

      put_test_env(:tenant_seeder, Brando.Tenant.Seeder)
      put_test_env(:tenant_structure_cloner, Brando.TenantCloners)
      put_test_env(:environment_schema_cloner, Brando.TenantCloners)

      {:ok, site} =
        Brando.Tenant.Setup.create_site(
          %{name: "Acme", key: "acme", languages: ["en"], default_language: "en", status: :active},
          user
        )

      %{acme: site, production: Enum.find(site.environments, & &1.live)}
    end

    test "are changed here, and a language added is seeded in each environment", %{
      conn: conn,
      acme: site,
      current_user: user
    } do
      {:ok, view, _html} = live(conn, "/admin/sites")

      view
      |> form("#languages-site-#{site.id}", site: %{id: site.id, languages: "no, en", default_language: "no"})
      |> render_submit()

      site = Registry.get_site(site.id)
      assert site.languages == ["no", "en"]
      assert site.default_language == "no"

      for environment <- site.environments do
        Brando.Tenant.with_prefix(Brando.Tenant.prefix(site, environment), fn ->
          assert Brando.Repo.get_by!(Brando.Pages.Page, uri: "index", language: :no).creator_id == user.id
        end)
      end

      refute has_element?(view, "#seeding-site-#{site.id}")
    end

    test "the form says before saving that a language removed keeps its content", %{conn: conn, acme: site} do
      {:ok, site} = Registry.update_site(site, %{languages: ["en", "no"]})
      {:ok, view, _html} = live(conn, "/admin/sites")

      refute has_element?(view, "#languages-site-#{site.id} [role=status]")

      view
      |> form("#languages-site-#{site.id}", site: %{id: site.id, languages: "en", default_language: "en"})
      |> render_change()

      assert has_element?(view, "#languages-site-#{site.id} [role=status]", "Removing no deletes nothing")
    end

    test "what was typed in one field stays while the other is edited, and is what gets saved",
         %{conn: conn, acme: site} do
      {:ok, view, _html} = live(conn, "/admin/sites")
      form_id = "#languages-site-#{site.id}"

      view
      |> form(form_id, site: %{id: site.id, languages: "en,no"})
      |> render_change()

      # The card re-renders on each change: both fields show the draft, so the
      # browser does not put the saved value back in the one not being typed in
      assert view |> element(~s(#{form_id} input[name="site[languages]"])) |> render() =~ ~s(value="en,no")

      view
      |> form(form_id, site: %{default_language: "no"})
      |> render_change()

      assert view |> element(~s(#{form_id} input[name="site[languages]"])) |> render() =~ ~s(value="en,no")
      assert view |> element(~s(#{form_id} input[name="site[default_language]"])) |> render() =~ ~s(value="no")

      # Submitting what the form holds, with nothing typed anew
      view |> form(form_id) |> render_submit()

      site = Registry.get_site(site.id)
      assert site.languages == ["en", "no"]
      assert site.default_language == "no"

      # Saved: the form is back on the site's own values
      assert view |> element(~s(#{form_id} input[name="site[languages]"])) |> render() =~ ~s(value="en,no")
    end

    test "the default is not removed without a new default", %{conn: conn, acme: site} do
      {:ok, site} = Registry.update_site(site, %{languages: ["en", "no"], default_language: "no"})
      {:ok, view, _html} = live(conn, "/admin/sites")

      view
      |> form("#languages-site-#{site.id}", site: %{id: site.id, languages: "en", default_language: "no"})
      |> render_submit()

      assert Registry.get_site(site.id).languages == ["en", "no"]
    end

    test "in groups mode, a user who may not update sites cannot change them", %{editor: editor, acme: site} do
      put_test_env(:authorization_mode, :groups)
      {:ok, _} = Brando.Authorization.Migration.run()

      assert {:error, :forbidden} = Brando.Tenant.Setup.update_languages(site, %{languages: ["en", "no"]}, editor)
      assert Registry.get_site(site.id).languages == ["en"]
    end

    test "shows the seeding queued, a failed attempt, what is missing, and seeds it again", %{
      conn: conn,
      acme: site,
      production: production
    } do
      row = "#seeding-#{site.id}-#{production.id}-no"

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, _site} = Registry.update_site(site, %{languages: ["en", "no"]})
      end)

      {:ok, view, _html} = live(conn, "/admin/sites")
      assert has_element?(view, row, "Seeding no in Production")
      refute has_element?(view, "#{row} button")
      # Under the languages form it reports on, not under the library group
      assert has_element?(view, "#languages-site-#{site.id} + .site-seeding #seeding-site-#{site.id} #{row}")

      Brando.Repo.update_all(Oban.Job, [set: [state: "retryable", attempt: 1, errors: [%{"error" => "boom\nstack"}]]],
        prefix: "public"
      )

      view |> element("button", "Refresh") |> render_click()
      assert has_element?(view, row, "failed, and is retried (attempt 1 of 20): boom")
      assert has_element?(view, "#{row} button", "Seed again")

      # Its last attempt failed
      Brando.Repo.update_all(Oban.Job, [set: [state: "discarded", attempt: 3]], prefix: "public")
      view |> element("button", "Refresh") |> render_click()
      assert has_element?(view, row, "Seeding no in Production failed: boom")

      # Pruned, it leaves what is missing
      Brando.Repo.delete_all(Oban.Job, prefix: "public")
      view |> element("button", "Refresh") |> render_click()
      assert has_element?(view, row, "Production has no starting content in no.")

      view |> element("#{row} button", "Seed again") |> render_click()
      refute has_element?(view, row)

      Brando.Tenant.with_prefix(Brando.Tenant.prefix(site, production), fn ->
        assert Brando.Repo.get_by(Brando.Pages.Page, uri: "index", language: :no)
      end)
    end

    test "shows a failed seeding where the identity exists, and seeds it again", %{
      conn: conn,
      acme: site,
      production: production
    } do
      row = "#seeding-#{site.id}-#{production.id}-no"

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, _site} = Registry.update_site(site, %{languages: ["en", "no"]})
      end)

      Brando.Tenant.with_prefix(Brando.Tenant.prefix(site, production), fn ->
        Brando.Sites.create_default_identity(:no)
      end)

      Brando.Repo.update_all(
        Oban.Job,
        [set: [state: "discarded", attempt: 3, errors: [%{"attempt" => 3, "error" => "no homepage"}]]],
        prefix: "public"
      )

      {:ok, view, _html} = live(conn, "/admin/sites")
      assert has_element?(view, row, "Seeding no in Production failed: no homepage")

      # A new job runs beside the discarded one (inline in tests, which keeps
      # no row of it)
      view |> element("#{row} button", "Seed again") |> render_click()

      Brando.Tenant.with_prefix(Brando.Tenant.prefix(site, production), fn ->
        assert Brando.Repo.get_by(Brando.Pages.Page, uri: "index", language: :no)
      end)
    end

    test "says in words why it cannot seed", %{conn: conn, acme: site, production: production, current_user: user} do
      Brando.endpoint().subscribe("user:#{user.id}")
      {:ok, view, _html} = live(conn, "/admin/sites")

      seed = fn environment_id, language ->
        render_click(view, "seed_language", %{
          "site-id" => to_string(site.id),
          "environment-id" => to_string(environment_id),
          "language" => language
        })
      end

      seed.(production.id, "no")
      assert_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{level: :error, payload: message}}
      assert message == "no is not one of Acme’s languages."

      seed.(0, "en")
      assert_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{level: :error, payload: message}}
      assert message == "That environment is not one of Acme’s."
    end

    test "while one of its own seedings runs, says so, and seeds a sibling again", %{
      conn: conn,
      acme: site,
      production: production,
      current_user: user
    } do
      staging = Enum.find(site.environments, &(not &1.live))
      production_row = "#seeding-#{site.id}-#{production.id}-no"
      staging_row = "#seeding-#{site.id}-#{staging.id}-no"

      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, _site} = Registry.update_site(site, %{languages: ["en", "no"]})
      end)

      job = fn environment ->
        prefix = Brando.Tenant.prefix(site, environment)
        from(j in Oban.Job, where: fragment("?->>'tenant_prefix'", j.args) == ^prefix)
      end

      Brando.Repo.update_all(job.(staging), [set: [state: "executing", attempt: 1]], prefix: "public")

      Brando.Repo.update_all(
        job.(production),
        [set: [state: "retryable", attempt: 1, errors: [%{"attempt" => 1, "error" => "boom"}]]],
        prefix: "public"
      )

      # The running job holds the locks a copy holds
      {:ok, lock_conn} =
        Postgrex.start_link(Keyword.drop(Brando.Repo.repo().config(), [:pool, :ownership_pool, :pool_size, :name]))

      key = Brando.Tenant.Lock.environment_operation_key(site.id)
      Postgrex.query!(lock_conn, "SELECT pg_advisory_lock(hashtextextended($1, 0))", [key])

      Brando.endpoint().subscribe("user:#{user.id}")
      {:ok, view, _html} = live(conn, "/admin/sites")

      assert has_element?(view, staging_row, "Seeding no in Staging now")
      refute has_element?(view, "#seeding-site-#{site.id}", "copy or setup")

      view |> element("#{production_row} button", "Seed again") |> render_click()
      assert_receive %Phoenix.Socket.Broadcast{event: "toast", payload: %{payload: "Seeding queued."}}
    end

    test "offers no seeding while an environment is copied or the site provisioned", %{
      conn: conn,
      acme: site,
      production: production
    } do
      row = "#seeding-#{site.id}-#{production.id}-no"
      {:ok, _site} = Registry.update_site(site, %{languages: ["en", "no"]})

      Brando.Tenant.with_prefix(Brando.Tenant.prefix(site, production), fn ->
        Brando.Repo.delete_all(Brando.Sites.Identity)
      end)

      {:ok, lock_conn} =
        Postgrex.start_link(Keyword.drop(Brando.Repo.repo().config(), [:pool, :ownership_pool, :pool_size, :name]))

      key = Brando.Tenant.Lock.environment_operation_key(site.id)
      Postgrex.query!(lock_conn, "SELECT pg_advisory_lock(hashtextextended($1, 0))", [key])

      {:ok, view, _html} = live(conn, "/admin/sites")
      assert has_element?(view, row, "Production has no starting content in no.")
      refute has_element?(view, "#{row} button")
      assert has_element?(view, row, "copy or setup")

      render_click(view, "seed_language", %{
        "site-id" => to_string(site.id),
        "environment-id" => to_string(production.id),
        "language" => "no"
      })

      Brando.Tenant.with_prefix(Brando.Tenant.prefix(site, production), fn ->
        refute Brando.Repo.get_by(Brando.Sites.Identity, language: :no)
      end)

      Postgrex.query!(lock_conn, "SELECT pg_advisory_unlock(hashtextextended($1, 0))", [key])
      view |> element("button", "Refresh") |> render_click()
      assert has_element?(view, "#{row} button", "Seed again")
    end
  end

  test "non-superusers are redirected", %{editor: editor, site: site} do
    assert {:ok, _assignment} = Access.grant(editor, site, :admin)
    conn = log_in_user(Phoenix.ConnTest.build_conn(), editor)

    assert {:error, {:redirect, %{to: "/admin"}}} = live(conn, "/admin/sites")
  end
end

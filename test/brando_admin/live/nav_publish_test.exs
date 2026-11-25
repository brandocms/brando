defmodule BrandoAdmin.NavPublishTest do
  # The Publish button under the site switcher (`Brando.SSG.Publishing`):
  # who sees it, its states, its panel and its actions
  use Brando.LiveCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Brando.Activity.Event
  alias Brando.Environments
  alias Brando.SSG.Build
  alias Brando.SSG.Builds
  alias Brando.Tenant
  alias Brando.Tenant.Registry

  defmodule Migrator do
    @behaviour Brando.Environments.Migrator

    @impl true
    def migrate(_site, _environment), do: {:ok, []}
  end

  defmodule Builder do
    def build(_site, _environment, opts) do
      File.mkdir_p!(opts[:output_path])
      File.write!(Path.join(opts[:output_path], "index.html"), "built")
      {:ok, %{file_count: 1, total_size: 5, url_count: 1, processed_urls: 1, failed_urls: []}}
    end
  end

  defmodule FailingBuilder do
    def build(_site, _environment, _opts), do: {:error, :renderer_down}
  end

  setup %{current_user: user} do
    root = Path.join(System.tmp_dir!(), "brando-nav-publish-#{System.unique_integer([:positive])}")
    put_test_env(:tenancy_mode, :multi)
    put_test_env(:sites_path, Path.join(root, "sites"))
    put_test_env(:media_path, Path.join(root, "media"))
    put_test_env(:tenant_migrator, Migrator)
    put_test_env(:tenant_structure_cloner, Brando.TenantCloners)
    put_test_env(:environment_schema_cloner, Brando.TenantCloners)
    put_test_env(:ssg_builder, Builder)
    Tenant.put_prefix(nil)
    Tenant.Cache.clear()

    on_exit(fn ->
      File.rm_rf(root)
      Tenant.put_prefix(nil)
      Tenant.Cache.clear()
    end)

    key = "nav-publish-#{System.unique_integer([:positive])}"

    {:ok, site} =
      Registry.create_site(%{
        name: "Nav Acme",
        key: key,
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :static,
        deploy_config: %{strategy: :local}
      })

    production = environment!(site, "production", true)
    staging = environment!(site, "staging", false)

    %{user: user, site: Registry.get_site(site.id), production: production, staging: staging}
  end

  defp environment!(site, key, live) do
    {:ok, environment} =
      Environments.create_environment(site, %{name: key, key: key, live: live, domain: "#{key}.#{site.key}.test"},
        actor: :system
      )

    environment
  end

  defp nav(c, opts \\ []) do
    conn = if user = opts[:as], do: c.conn |> recycle() |> log_in_user(user), else: c.conn
    environment = opts[:environment] || c.production

    {:ok, nav, _html} =
      live_isolated(conn, BrandoAdmin.Nav,
        session: %{
          "user_token" => get_session(conn, :user_token),
          "brando_site_key" => c.site.key,
          "brando_environment_key" => environment.key,
          "current_url" => "/admin"
        }
      )

    nav
  end

  defp open_panel(nav) do
    render_hook(nav, "publish_panel", %{})
    nav
  end

  defp manual(fun), do: Oban.Testing.with_testing_mode(:manual, fun)

  defp event!(c, schema, title, inserted_at) do
    Tenant.with_prefix(Tenant.prefix(c.site, c.production), fn ->
      Brando.Repo.insert!(%Event{
        action: :updated,
        schema: to_string(schema),
        entry_id: System.unique_integer([:positive]),
        title: title,
        user_id: c.user.id,
        inserted_at: inserted_at
      })
    end)
  end

  defp member(c, capabilities) do
    put_test_env(:authorization_mode, :groups)
    {:ok, _} = Brando.Authorization.Migration.run()
    Brando.SSGSSHFixtures.publishing_member(c.site, c.user, capabilities)
  end

  # The queries of the Publish button: those on the build, job and content
  # change tables, and the activity log, made while `fun` runs
  defp button_queries(fun) do
    test = self()
    handler = "nav-publish-queries-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:brando_integration, :repo, :query],
      fn _event, _measurements, %{source: source}, _config ->
        if source in ["ssg_builds", "oban_jobs", "ssg_content_changes", "activity_events"],
          do: send(test, {:button_query, source})
      end,
      nil
    )

    try do
      result = fun.()
      {result, collect_queries([])}
    after
      :telemetry.detach(handler)
    end
  end

  defp collect_queries(acc) do
    receive do
      {:button_query, source} -> collect_queries([source | acc])
    after
      0 -> acc
    end
  end

  describe "who sees it" do
    test "someone who may build and deploy, in the environment the site publishes from", c do
      assert has_element?(nav(c), "#publish.publish--changes [data-testid=publish-button]")
      refute has_element?(nav(c, environment: c.staging), "#publish")

      # Once a staging build is deployed, staging is where it publishes from
      {:ok, _build} = Builds.request_build(c.site, c.staging, creator_id: c.user.id, auto_deploy: true)
      refute has_element?(nav(c), "#publish")
      assert has_element?(nav(c, environment: c.staging), "#publish.publish--published")
    end

    test "nobody on a dynamic site or one without a deploy target, and no read is made", c do
      {:ok, _site} = Registry.update_site(c.site, %{delivery_mode: :dynamic})
      Tenant.Cache.clear()
      {nav, queries} = button_queries(fn -> nav(c) end)
      refute has_element?(nav, "#publish")
      assert queries == []

      {:ok, _site} = Registry.update_site(c.site, %{delivery_mode: :static, deploy_config: %{strategy: nil}})
      Tenant.Cache.clear()
      refute has_element?(nav(c), "#publish")
    end

    test "with capabilities, not someone who may only build, and without a read", c do
      builder = member(c, ["brando.publishing.build"])
      {nav, queries} = button_queries(fn -> nav(c, as: builder) end)
      refute has_element?(nav, "#publish")
      assert queries == []

      assert has_element?(nav(c, as: member(c, ["brando.publishing.build", "brando.publishing.deploy"])), "#publish")
    end

    test "a page load reads a fixed few times for it", c do
      {:ok, _build} = Builds.request_build(c.site, c.production, creator_id: c.user.id, auto_deploy: true)
      {_nav, queries} = button_queries(fn -> nav(c) end)
      # Twice mounted (the first render and the connected one), five at most each
      assert length(queries) <= 10
    end
  end

  describe "its states" do
    test "publishing, then published, as the worker goes", c do
      manual(fn -> {:ok, _build} = Brando.SSG.Publishing.publish(c.site, c.production, c.user) end)
      nav = nav(c)
      assert has_element?(nav, "#publish.publish--publishing")
      render_hook(nav, "publish", %{})
      assert [_one] = Builds.list_builds(c.site)

      [job] = Brando.Repo.all(from(j in Oban.Job, where: j.worker == "Brando.Worker.SSGBuild"), prefix: "public")
      :ok = Brando.Worker.SSGBuild.perform(job)
      from(j in Oban.Job, where: j.id == ^job.id) |> Brando.Repo.update_all([set: [state: "completed"]], prefix: "public")

      # The worker's broadcasts reach the navigation
      assert render(nav) =~ "publish--published"
    end

    test "unpublished changes, then published, from the panel's Publish", c do
      nav = nav(c) |> open_panel()
      assert has_element?(nav, "#publish.publish--changes")
      nav |> element("#publish-panel button[phx-click=publish]") |> render_click()
      assert has_element?(nav, "#publish.publish--published")
    end

    test "failed, with Try again; someone who may configure gets the build's row", c do
      put_test_env(:ssg_builder, FailingBuilder)
      nav = nav(c)
      nav |> open_panel() |> element("#publish-panel button[phx-click=publish]") |> render_click()
      assert has_element?(nav, "#publish.publish--failed")

      [build] = Builds.list_builds(c.site)
      nav |> open_panel()
      assert has_element?(nav, "#publish-panel a[href='/admin/config/publishing#ssg-build-#{build.id}']")

      put_test_env(:ssg_builder, Builder)
      nav |> element("#publish-panel button[phx-click=publish_retry]") |> render_click()
      assert has_element?(nav, "#publish.publish--published")
    end

    test "ready after Preview first, and Publish this build deploys that build", c do
      nav = nav(c) |> open_panel()
      nav |> element("#publish-panel button[phx-click=publish_preview]") |> render_click()
      assert has_element?(nav, "#publish.publish--ready")

      [build] = Builds.list_builds(c.site)
      nav |> open_panel()
      assert has_element?(nav, "#publish-panel a[target=_blank][href*='/__ssg_preview__/#{build.preview_token}/']")

      nav |> element("#publish-panel button[phx-click=publish_build][phx-value-id='#{build.id}']") |> render_click()
      assert has_element?(nav, "#publish.publish--published")
      assert Builds.get_build(build.id).status == :deployed
    end

    test "a save during the build ends in unpublished changes after the deploy", c do
      manual(fn -> {:ok, _build} = Brando.SSG.Publishing.publish(c.site, c.production, c.user) end)
      nav = nav(c)
      [job] = Brando.Repo.all(from(j in Oban.Job, where: j.worker == "Brando.Worker.SSGBuild"), prefix: "public")
      [build] = Builds.list_builds(c.site)
      {:ok, _building} = Builds.update(build, %{status: :building, started_at: DateTime.utc_now()})

      event!(c, Brando.Pages.Page, "Saved while building", DateTime.utc_now())
      :ok = Brando.Worker.SSGBuild.perform(job)
      from(j in Oban.Job, where: j.id == ^job.id) |> Brando.Repo.update_all([set: [state: "completed"]], prefix: "public")

      assert Builds.get_build(build.id).status == :deployed
      assert render(nav) =~ "publish--changes"
    end
  end

  describe "the panel" do
    test "lists what will go out, of the kinds the user may read, and counts the rest the same way", c do
      {:ok, deployed} = Builds.request_build(c.site, c.production, creator_id: c.user.id, auto_deploy: true)
      deployed = Builds.get_build(deployed.id)
      since = deployed.started_at

      # Before the deployed build: not listed
      event!(c, Brando.Pages.Page, "Old page", DateTime.add(since, -60, :second))
      event!(c, Brando.Pages.Page, "Readable page", DateTime.add(since, 1, :second))

      for n <- 1..20,
          do: event!(c, Brando.Pages.Fragment, "Hidden fragment #{n}", DateTime.add(since, 10 + n, :second))

      publisher = member(c, ["brando.publishing.build", "brando.publishing.deploy", "brando.pages.read"])
      nav = nav(c, as: publisher) |> open_panel()

      assert has_element?(nav, "#publish-panel .publish-change", "Readable page")
      refute has_element?(nav, "#publish-panel .publish-change", "Hidden fragment")
      refute has_element?(nav, "#publish-panel .publish-change", "Old page")
      refute has_element?(nav, "#publish-panel [data-rest]")

      # A superuser reads them all: twenty listed, one more counted
      nav = nav(c) |> open_panel()
      assert nav |> element("#publish-panel .publish-panel__changes") |> render() =~ "Hidden fragment 20"
      refute nav |> element("#publish-panel .publish-panel__changes") |> render() =~ "Readable page"
      assert has_element?(nav, "#publish-panel [data-rest='1']")
    end

    test "goes with the button when the user's grants are removed while it is open", c do
      publisher = member(c, ["brando.publishing.build", "brando.publishing.deploy"])
      nav = nav(c, as: publisher) |> open_panel()
      assert has_element?(nav, "#publish-panel")

      scope = Brando.Authorization.Scope.site(c.user, c.site)
      {:ok, groups} = Brando.Authorization.Groups.list(scope)
      [group] = Enum.filter(groups, &String.starts_with?(&1.name, "Publishing "))

      {:ok, _group} =
        Brando.Authorization.Groups.update(
          scope,
          group.id,
          %{},
          ["brando.admin.access", "brando.publishing.read", "brando.publishing.build"],
          group.lock_version
        )

      refute render(nav) =~ ~s(id="publish")
    end

    test "a crafted Publish from someone who may not deploy starts nothing", c do
      builder = member(c, ["brando.publishing.build"])
      nav = nav(c, as: builder)

      render_hook(nav, "publish", %{})
      render_hook(nav, "publish_retry", %{})
      render_hook(nav, "publish_build", %{"id" => "1"})

      assert Builds.list_builds(c.site) == []
    end
  end

  describe "legacy mode" do
    test "an editor of the site sees no button, an admin does", c do
      editor = Brando.Factory.insert(:random_user, role: :editor, config: %Brando.Users.UserConfig{})
      {:ok, _} = Brando.Tenant.Access.grant(editor, c.site, :editor)
      refute has_element?(nav(c, as: editor), "#publish")

      render_hook(nav(c, as: editor), "publish", %{})
      assert Builds.list_builds(c.site) == []

      admin = Brando.Factory.insert(:random_user, role: :admin, config: %Brando.Users.UserConfig{})
      {:ok, _} = Brando.Tenant.Access.grant(admin, c.site, :admin)
      assert has_element?(nav(c, as: admin), "#publish")
    end
  end

  test "a build that turns out deployed elsewhere moves the button", c do
    nav = nav(c)
    assert has_element?(nav, "#publish")

    {:ok, %Build{}} = Builds.request_build(c.site, c.staging, creator_id: c.user.id, auto_deploy: true)
    refute render(nav) =~ ~s(id="publish")
  end
end

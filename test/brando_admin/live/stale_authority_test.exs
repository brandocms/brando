defmodule BrandoAdmin.StaleAuthorityTest do
  # Authority is read when it is used, not when a view mounted: a demoted
  # account, a revoked site or a lost read grant takes effect on an open view's
  # next action, and an unrelated change disturbs nobody.
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.{Boundary, Groups, Migration, Operations, Scope}
  alias Brando.Content.Definition.Archive
  alias Brando.Content.Definitions
  alias Brando.Pages.Page
  alias Brando.Tenant
  alias Brando.Tenant.{Access, Cache, Registry, Setup}
  alias Brando.Users
  alias Brando.Users.{SecurityPolicy, User, UserSite}
  alias Brando.Webhooks.Webhook

  defp superuser, do: Brando.Test.Users.insert_user(role: :superuser)

  defp account(role),
    do: Factory.insert(:random_user, role: role, language: :en, avatar: nil, config: %Users.UserConfig{})

  defp demote(user, role \\ :editor) do
    {:ok, demoted} = Users.update_user(user.id, %{role: role}, superuser())
    demoted
  end

  # A template whose unquote runs while the module is defined, without any
  # render, and sets only `marker`.
  defp bundle(marker, uid \\ "hero-test") do
    template = ~s|template :heex, ~S"<div>{unquote(:persistent_term.put(:#{marker}, true) && 1)}</div>"|

    source =
      "test/fixtures/definitions/hero.exs.txt"
      |> File.read!()
      |> String.replace("hero-test", uid)
      |> then(&Regex.replace(~r/template :heex, .*$/m, &1, template))

    {:ok, binary} = Archive.pack(%{"hero.exs" => source})
    on_exit(fn -> :persistent_term.erase(marker) end)
    binary
  end

  defp compiled?(marker), do: :persistent_term.get(marker, false)

  defp plan(binary, actor) do
    {:ok, archive} = Archive.read(binary)
    Definitions.plan(archive.bundle, actor)
  end

  defp install_hero(user) do
    {:ok, binary} = Archive.pack(%{"hero.exs" => File.read!("test/fixtures/definitions/hero.exs.txt")})
    {:ok, archive} = Archive.read(binary)
    {:ok, plan} = Definitions.plan(archive.bundle, user)
    {:ok, _} = Definitions.apply(plan, user)
  end

  defp preview_zip(view, binary) do
    view
    |> file_input("#module-files-import-form", :definition_zip, [
      %{name: "modules.zip", content: binary, type: "application/zip"}
    ])
    |> render_upload("modules.zip")

    view |> form("#module-files-import-form", references: "") |> render_submit()
  end

  # A lowered role ends the view's process, which the client rejoins at the
  # stored role: e2e/playwright/tests/users/stale-authority.spec.js sees that.
  # The test process is linked to the view, and goes on.
  defp watch(view) do
    Process.flag(:trap_exit, true)
    Process.monitor(view.pid)
  end

  defp assert_remounted(ref) do
    assert_receive {:DOWN, ^ref, :process, _, {:shutdown, :authority_changed}}, 1000
  end

  # A write no broadcast tells of, as from another node or the database
  defp lower_unannounced(user, role),
    do: Repo.update_all(from(u in User, where: u.id == ^user.id), set: [role: role])

  # The event arrives, whatever was missed: the view ends, and does not act.
  defp assert_event_ends_view(view, fun) do
    ref = watch(view)
    catch_exit(fun.())
    assert_remounted(ref)
  end

  defp refute_remounted(ref) do
    refute_receive {:DOWN, ^ref, :process, _, _}, 100
  end

  describe "module code in an open view, legacy mode (audit F15)" do
    setup do
      put_test_env(:authorization_mode, :legacy)
      put_test_env(:tenancy_mode, :none)
    end

    test "a ZIP previewed after a demotion compiles nothing", c do
      {:ok, view, _} = live(c.conn, "/admin/config/content/modules")

      # Unannounced: a LiveComponent's event, which passes no view hook, is what
      # reaches the preview, so the fresh read has to hold by itself.
      lower_unannounced(c.current_user, :editor)

      html = preview_zip(view, bundle(:stale_authority_open_view))

      refute compiled?(:stale_authority_open_view)
      refute html =~ "Review import"
    end

    test "a plan by a held struct compiles nothing, for a new module and an existing one", c do
      held = c.current_user
      install_hero(held)
      demote(held)

      assert {:error, _} = plan(bundle(:stale_authority_existing), held)
      refute compiled?(:stale_authority_existing)

      assert {:error, _} = plan(bundle(:stale_authority_new, "fresh-module"), held)
      refute compiled?(:stale_authority_new)
    end

    test "a superuser's plan still compiles", c do
      assert {:ok, _} = plan(bundle(:stale_authority_control), c.current_user)
      assert compiled?(:stale_authority_control)
    end

    test "the boundary reads the role afresh for a held struct", c do
      held = c.current_user
      install_hero(held)
      module = Repo.get_by!(Brando.Content.Module, uid: "hero-test")
      demote(held, :user)

      assert {:error, :forbidden} = Boundary.authorize(held, :create, Brando.Content.Module)
      assert {:error, :forbidden} = Boundary.authorize_record(held, :update, Brando.Content.Module, module.id)
      assert {:error, :forbidden} = Boundary.change(held, :update, Ecto.Changeset.change(module, name: "Changed"))
      assert {:error, :forbidden} = Boundary.authorize(held, :update, Page)
    end
  end

  describe "module code in an open view, groups mode (audit F15)" do
    setup %{current_user: owner} do
      put_test_env(:authorization_mode, :groups)
      put_test_env(:tenancy_mode, :single)
      put_test_env(:site_key, "stale-groups")
      Cache.clear()
      on_exit(&Cache.clear/0)

      site = site("stale-groups")
      environment = environment(site, "production", true)
      {:ok, _} = Migration.run()
      Tenant.put_prefix(Tenant.prefix(site, environment))
      on_exit(fn -> Tenant.put_prefix(nil) end)
      %{owner: owner, site: site}
    end

    test "losing the superuser group stops the compile", c do
      held = superuser()
      {:ok, _} = Migration.run()
      assert {:ok, _} = plan(bundle(:stale_groups_control), held)
      assert compiled?(:stale_groups_control)

      installation = Scope.installation(c.owner)
      {:ok, groups} = Groups.list(installation)
      for group <- groups, do: Groups.remove_member(installation, group.id, held.id)

      refute Boundary.superuser?(held)
      assert {:error, _} = plan(bundle(:stale_groups_after), held)
      refute compiled?(:stale_groups_after)
    end
  end

  describe "role gates with a held struct, legacy mode (audit F19)" do
    setup do
      put_test_env(:authorization_mode, :legacy)
      put_test_env(:tenancy_mode, :none)
    end

    test "every gate reads the stored role", c do
      held = c.current_user
      assert Users.superuser?(held)

      demote(held, :user)

      refute Users.superuser?(held)
      refute Brando.Webhooks.can_manage?(held)
      refute Brando.Notifications.Routing.can_manage?(held)
      refute Brando.MCP.can_manage_here?(held)
      refute Brando.MCP.can_manage?(held, %{site: nil, environment: nil, prefix: nil})
      refute Brando.ListingViews.moderator?(held)
      refute Brando.AI.Agent.Guidance.configurable?(held)
      assert {:error, :forbidden} = SecurityPolicy.update(%{"two_factor" => "off"}, held)
    end

    test "a raised role counts at once too", c do
      held = account(:editor)
      refute Users.superuser?(held)
      {:ok, _} = Users.update_user(held.id, %{role: :superuser}, c.current_user)
      assert Users.superuser?(held)
    end

    test "a demotion remounts an open view at once", c do
      {:ok, view, _} = live(c.conn, "/admin/users/sign-in-policy")
      ref = watch(view)

      demote(c.current_user, :user)

      assert_remounted(ref)
    end

    test "a demotion no broadcast told of ends the view on its next event, which does nothing", c do
      {:ok, view, _} = live(c.conn, "/admin/users/sign-in-policy")
      before = SecurityPolicy.get()

      lower_unannounced(c.current_user, :user)

      assert_event_ends_view(view, fn ->
        render_submit(view, "save", %{"policy" => %{"two_factor" => "everyone"}})
      end)

      assert SecurityPolicy.get().two_factor == before.two_factor
    end

    test "a new mount at the lowered role is refused", c do
      demote(c.current_user, :user)
      assert {:error, {:live_redirect, %{to: "/admin/users"}}} = live(c.conn, "/admin/users/sign-in-policy")
    end

    test "a raised role keeps the view and its assigns follow", c do
      user = account(:editor)
      conn = log_in_user(build_conn(), user)
      {:ok, view, _} = live(conn, "/admin/pages")
      ref = watch(view)

      {:ok, _} = Users.update_user(user.id, %{role: :admin}, c.current_user)

      assert render(view)
      assert :sys.get_state(view.pid).socket.assigns.current_user.role == :admin
      refute_remounted(ref)
    end

    test "a user's save tells open views to check again, and an editor's view is not disturbed", c do
      user = account(:editor)
      conn = log_in_user(build_conn(), user)
      {:ok, view, _} = live(conn, "/admin/pages")
      ref = watch(view)
      Phoenix.PubSub.subscribe(Brando.pubsub(), "brando:authorization")

      {:ok, _} = Users.update_user(user.id, %{name: "Renamed"}, c.current_user)

      assert_receive {:authorization_changed, :all}
      assert render(view)
      refute_remounted(ref)
    end

    test "the webhook screen creates nothing after a demotion", c do
      {:ok, view, _} = live(c.conn, "/admin/config/webhooks/new")
      lower_unannounced(c.current_user, :user)

      assert_event_ends_view(view, fn ->
        render_submit(view, "save", %{"webhook" => %{"name" => "Late", "url" => "https://hooks.example.com/late"}})
      end)

      assert Repo.all(Webhook) == []
      refute Brando.Webhooks.can_manage?(c.current_user)
    end
  end

  describe "site gates, legacy mode (audit F19)" do
    setup do
      put_test_env(:authorization_mode, :legacy)
      put_test_env(:tenancy_mode, :multi)
      Cache.clear()
      Tenant.put_prefix(nil)

      on_exit(fn ->
        Cache.clear()
        Tenant.put_prefix(nil)
      end)

      site = site("stale-gates")
      %{site: site, environment: environment(site, "production", true)}
    end

    test "the sites screen grants nothing to the demoted account", c do
      {:ok, view, _} = live(c.conn, "/admin/sites")
      lower_unannounced(c.current_user, :user)

      assert_event_ends_view(view, fn ->
        render_submit(view, "grant", %{
          "assignment" => %{"site_id" => c.site.id, "user_id" => c.current_user.id, "role" => "admin"}
        })
      end)

      refute Repo.exists?(from(a in UserSite, where: a.user_id == ^c.current_user.id), prefix: "public")

      assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = live(c.conn, "/admin/sites")
    end

    test "a site's access reads the stored role of a held struct", c do
      held = c.current_user
      assert Access.role_for(held, c.site) == :superuser
      assert c.site.id in Enum.map(Access.list_sites(held), & &1.id)

      demote(held, :user)

      assert Access.role_for(held, c.site) == nil
      refute Access.can_access?(held, c.site)
      refute Access.can_manage?(held, c.site)
      assert Access.list_sites(held) == []
    end

    test "environment operations follow the stored role and the site's role", c do
      manager = account(:editor)
      {:ok, _} = Access.grant(manager, c.site, :admin)
      assert :ok = Operations.authorize(manager, :delete, :environments, c.site.id)

      {:ok, _} = Access.grant(manager, c.site, :editor)
      assert {:error, :forbidden} = Operations.authorize(manager, :delete, :environments, c.site.id)

      assert :ok = Operations.authorize(:system, :delete, :environments, c.site.id)
      assert :ok = Operations.authorize(nil, :delete, :environments, c.site.id)
    end

    test "a site's role lowered keeps the view open and refuses its actions", c do
      manager = account(:editor)
      {:ok, _} = Access.grant(manager, c.site, :admin)
      conn = c.conn |> recycle() |> log_in_user(manager)
      {:ok, view, _} = live(conn, "/admin/config/environments")
      ref = watch(view)

      {:ok, _} = Access.grant(manager, c.site, :editor)

      render_click(view, "delete_environment", %{"id" => c.environment.id})

      assert Registry.get_environment(c.environment.id)
      refute_remounted(ref)
    end

    test "the publishing screen saves nothing after a site's role is lowered", c do
      manager = account(:editor)
      {:ok, _} = Access.grant(manager, c.site, :admin)
      site = Registry.get_site(c.site.id)
      {:ok, _} = Registry.update_site(site, %{delivery_mode: :static})
      conn = c.conn |> recycle() |> log_in_user(manager)
      {:ok, view, _} = live(conn, "/admin/config/publishing")

      {:ok, _} = Access.grant(manager, site, :editor)

      render_submit(view, "save_deploy_config", %{"deploy" => %{"strategy" => "rsync", "target" => "x@y.test:/z"}})

      refute Registry.get_site(site.id).deploy_config.target == "x@y.test:/z"
    end
  end

  describe "a site's access in an open view, legacy mode (audit F21)" do
    setup do
      put_test_env(:authorization_mode, :legacy)
      put_test_env(:tenancy_mode, :multi)
      Cache.clear()
      Tenant.put_prefix(nil)

      on_exit(fn ->
        Cache.clear()
        Tenant.put_prefix(nil)
      end)

      page = Factory.insert(:page, title: "Before", uri: "stale-site", status: :draft)
      site = site("stale-site")
      environment = environment(site, "production", true)
      editor = account(:editor)
      {:ok, _} = Access.grant(editor, site, :editor)
      conn = log_in_user(build_conn(), editor)
      %{site: site, environment: environment, editor: editor, editor_conn: conn, page: page}
    end

    defp title(c) do
      [title] =
        Repo.all(from(p in Page, where: p.id == ^c.page.id, select: p.title),
          prefix: Tenant.prefix(c.site, c.environment)
        )

      title
    end

    # A site no longer enterable ends the sticky views too, which takes LiveViewTest's
    # one client with them. These tests look at the page's own view.
    defp live_page(conn, path) do
      {:ok, view, _} = live(conn, path)

      for child <- live_children(view) do
        :sys.replace_state(child.pid, fn state ->
          Phoenix.PubSub.unsubscribe(Brando.pubsub(), "brando:authorization")
          state
        end)
      end

      view
    end

    test "revoking ends the view, on a LiveView event's screen and on the page form", c do
      list = live_page(c.editor_conn, "/admin/pages")
      form = live_page(c.editor_conn, "/admin/pages/update/#{c.page.id}")

      :ok = Access.revoke(c.editor, c.site)

      assert_redirect(list, "/admin/access-denied")
      assert_redirect(form, "/admin/access-denied")
      assert title(c) == "Before"
    end

    test "suspending the site ends the view", c do
      form = live_page(c.editor_conn, "/admin/pages/update/#{c.page.id}")
      {:ok, _} = Setup.suspend_site(c.site, actor: c.current_user)
      assert_redirect(form, "/admin/access-denied")
    end

    test "archiving the site ends the view", c do
      form = live_page(c.editor_conn, "/admin/pages/update/#{c.page.id}")
      {:ok, _} = Setup.suspend_site(c.site, actor: c.current_user)
      assert_redirect(form, "/admin/access-denied")

      {:ok, _} = Setup.activate_site(Registry.get_site(c.site.id), actor: c.current_user)
      form = live_page(c.editor_conn, "/admin/pages/update/#{c.page.id}")
      {:ok, _} = Setup.archive_site(Registry.get_site(c.site.id), actor: c.current_user)
      assert_redirect(form, "/admin/access-denied")
    end

    test "a revocation no broadcast told of is found on the next event", c do
      {:ok, view, _} = live(c.editor_conn, "/admin/pages")

      Repo.delete_all(from(a in UserSite, where: a.user_id == ^c.editor.id), prefix: "public")

      assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = render_click(view, "stale_authority_probe")
    end

    test "a suspension no broadcast told of is found on the next event", c do
      {:ok, view, _} = live(c.editor_conn, "/admin/pages")

      Repo.update_all(from(s in Brando.Sites.Site, where: s.id == ^c.site.id), set: [status: :suspended])

      assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = render_click(view, "stale_authority_probe")
    end

    test "someone else's revocation disturbs nobody, and keeps what was typed", c do
      other = account(:editor)
      {:ok, _} = Access.grant(other, c.site, :editor)
      {:ok, view, _} = live(c.editor_conn, "/admin/pages/update/#{c.page.id}")
      ref = watch(view)
      view |> form("#page_form_form", %{"page" => %{"title" => "Typed"}}) |> render_change()

      :ok = Access.revoke(other, c.site)

      assert view
             |> render()
             |> Floki.parse_document!()
             |> Floki.find("input[name='page[title]']")
             |> Floki.attribute("value") ==
               ["Typed"]

      refute_remounted(ref)
    end

    test "views with no catch-all handle_info survive the broadcast, the child views too", c do
      {:ok, view, _} = live(c.editor_conn, "/admin/users/password")

      Brando.Authorization.Realtime.broadcast_changed()

      assert render(view)
      assert Process.alive?(view.pid)
      for child <- live_children(view), do: assert(render(child))
    end

    test "a superuser suspending the site the session is on stays on the sites screen", c do
      view = on_site(c)

      # Told to this view alone: its sticky views end (below), and the test's client with them.
      Repo.update_all(from(s in Brando.Sites.Site, where: s.id == ^c.site.id), set: [status: :suspended])
      Cache.invalidate()
      send(view.pid, {:authorization_changed, :all})

      assert :sys.get_state(view.pid).socket.assigns.current_site.id == c.site.id
      assert render_click(view, "refresh") =~ "suspended"
    end

    defp on_site(c) do
      conn = post(c.conn, "/admin/environment", %{"site" => c.site.key})
      {:ok, view, _} = live(recycle(conn), "/admin/sites")
      view
    end

    # A sticky view by itself, as the client rejoins it: with the session the page
    # rendered it with, and its own LiveViewTest client.
    defp sticky(c, module \\ BrandoAdmin.Nav) do
      {:ok, view, _} =
        live_isolated(c.conn, module,
          session: %{
            "user_token" => get_session(c.conn, :user_token),
            "brando_site_key" => c.site.key,
            "current_url" => "/admin/sites"
          }
        )

      view
    end

    defp assigns_of(view), do: :sys.get_state(view.pid).socket.assigns

    test "suspending the site ends the sticky views, and they rejoin on none or another", c do
      refs =
        for module <- [BrandoAdmin.Nav, BrandoAdmin.Chrome, BrandoAdmin.CommandPaletteLive],
            do: c |> sticky(module) |> watch()

      {:ok, _} = Setup.suspend_site(c.site, actor: c.current_user)

      for ref <- refs, do: assert_remounted(ref)

      nav = sticky(c)
      refute assigns_of(nav).current_site
      render_click(nav, "toggle_nav", %{"minimized" => "true"})
      assert assigns_of(nav).minimized == "true"

      other = site("stale-site-other")
      environment(other, "production", true)

      nav = sticky(c)
      assert assigns_of(nav).current_site.id == other.id
      render_click(nav, "toggle_nav", %{"minimized" => "true"})
      assert assigns_of(nav).minimized == "true"
    end

    test "a suspension no broadcast told of ends a sticky view on its next event", c do
      view = on_site(c)
      nav = find_live_child(view, "brando-nav")

      Repo.update_all(from(s in Brando.Sites.Site, where: s.id == ^c.site.id), set: [status: :suspended])
      Cache.invalidate()

      assert_event_ends_view(nav, fn -> render_click(nav, "toggle_nav", %{"minimized" => "true"}) end)
    end

    # A rejoin asks the same cache: it would get the same site back, and a form's
    # recovery event would end the view again. It refuses until the cache has heard.
    test "a sticky view stays and refuses while a rejoin would resolve the same site", c do
      view = on_site(c)
      nav = find_live_child(view, "brando-nav")
      ref = watch(nav)

      Repo.update_all(from(s in Brando.Sites.Site, where: s.id == ^c.site.id), set: [status: :suspended])

      render_click(nav, "toggle_nav", %{"minimized" => "true"})
      refute_remounted(ref)
      refute assigns_of(nav)[:minimized] == "true"

      assert assigns_of(sticky(c)).current_site.id == c.site.id
    end

    test "a sticky view with an ended session takes no hooks, and survives a broadcast and an event", c do
      session = %{"user_token" => "ended", "current_url" => "/admin"}
      {:ok, nav, _} = live_isolated(c.conn, BrandoAdmin.Nav, session: session)
      {:ok, chrome, _} = live_isolated(c.conn, BrandoAdmin.Chrome, session: session)
      {:ok, palette, _} = live_isolated(c.conn, BrandoAdmin.CommandPaletteLive, session: session)

      refute assigns_of(nav).current_user
      # What `legacy_check` asks of a view only superusers may open: no, without a raise
      refute Boundary.superuser?(nil)

      Brando.Authorization.Realtime.broadcast_changed()

      for view <- [nav, chrome, palette], do: assert(render(view))

      render_click(nav, "toggle_nav", %{"minimized" => "true"})
      assert assigns_of(nav).minimized == "true"

      for view <- [nav, chrome, palette] do
        refute Map.has_key?(assigns_of(view), :legacy_site_rule)
        refute "brando:authorization" in Elixir.Registry.keys(Brando.pubsub(), view.pid)
      end
    end
  end

  describe "a site's access in an open view, groups mode" do
    setup %{current_user: owner} do
      put_test_env(:authorization_mode, :groups)
      put_test_env(:tenancy_mode, :multi)
      Cache.clear()
      Tenant.put_prefix(nil)

      on_exit(fn ->
        Cache.clear()
        Tenant.put_prefix(nil)
      end)

      Factory.insert(:page, title: "Before", uri: "stale-groups-site", status: :draft)
      site = site("stale-groups-site")
      environment(site, "production", true)
      {:ok, _} = Migration.run()
      editor = account(:editor)

      scope = Scope.site(owner, site)
      {:ok, group} = Groups.create(scope, %{name: "Readers"}, ~w(brando.admin.access brando.pages.read))
      {:ok, :ok} = Groups.add_member(scope, group.id, editor.id)

      %{site: site, editor: editor, group: group, scope: scope}
    end

    test "removing the membership and suspending the site end the view", c do
      conn = log_in_user(build_conn(), c.editor)

      {:ok, view, _} = live(conn, "/admin/pages")
      {:ok, :ok} = Groups.remove_member(c.scope, c.group.id, c.editor.id)
      assert_redirect(view, "/admin/access-denied")

      {:ok, :ok} = Groups.add_member(c.scope, c.group.id, c.editor.id)
      {:ok, view, _} = live(conn, "/admin/pages")
      {:ok, _} = Setup.suspend_site(c.site, actor: Scope.installation(c.current_user))
      assert_redirect(view, "/admin/access-denied")
    end
  end

  describe "the activity log (audit F44)" do
    defp create_page(user, title) do
      {:ok, page} =
        Brando.Pages.create_page(
          %{
            title: title,
            uri: "stale-#{System.unique_integer([:positive])}",
            language: "en",
            template: "default.html",
            status: :draft
          },
          user
        )

      page
    end

    setup do
      put_test_env(:tenancy_mode, :none)
    end

    test "a revoked read grant drops the type's rows from the open log", c do
      put_test_env(:authorization_mode, :groups)
      {:ok, _} = Migration.run()

      {conn, reader} = Brando.Test.Users.log_in_as(build_conn(), permissions: ~w(brando.activity.read))
      grant = Brando.Test.Users.grant_permissions(reader, ~w(brando.pages.read))
      create_page(c.current_user, "Before revocation")

      {:ok, view, _} = live(conn, "/admin/config/activity")
      assert has_element?(view, ".activity-entry", "Before revocation")

      {:ok, :ok} = Groups.remove_member(Scope.current(c.current_user), grant.id, reader.id)

      render(view)
      refute has_element?(view, ".activity-entry", "Before revocation")

      create_page(c.current_user, "After revocation")
      render_click(view, "load_more")
      refute has_element?(view, ".activity-entry", "After revocation")
    end

    test "a revocation no broadcast told of drops the rows on the next load", c do
      put_test_env(:authorization_mode, :groups)
      {:ok, _} = Migration.run()

      {conn, reader} = Brando.Test.Users.log_in_as(build_conn(), permissions: ~w(brando.activity.read))
      grant = Brando.Test.Users.grant_permissions(reader, ~w(brando.pages.read))
      create_page(c.current_user, "Before revocation")

      {:ok, view, _} = live(conn, "/admin/config/activity")
      assert has_element?(view, ".activity-entry", "Before revocation")
      [event] = Repo.all(Brando.Activity.Event)

      Repo.delete_all(from(m in Brando.Authorization.Membership, where: m.group_id == ^grant.id), prefix: "public")

      assert render_click(view, "compare", %{"id" => event.id})
      refute :sys.get_state(view.pid).socket.assigns.comparison

      render_click(view, "load_more")
      refute has_element?(view, ".activity-entry", "Before revocation")
    end

    test "an open comparison closes when the event is no longer readable", c do
      put_test_env(:authorization_mode, :groups)
      {:ok, _} = Migration.run()

      {conn, reader} = Brando.Test.Users.log_in_as(build_conn(), permissions: ~w(brando.activity.read))
      grant = Brando.Test.Users.grant_permissions(reader, ~w(brando.pages.read))
      create_page(c.current_user, "Compared")
      [event] = Repo.all(Brando.Activity.Event)

      {:ok, view, _} = live(conn, "/admin/config/activity")

      # What compare stores, whichever revisions the event has: closing does not depend on them.
      :sys.replace_state(view.pid, fn state ->
        put_in(state.socket.assigns[:comparison], %{event: event, result: :error})
      end)

      {:ok, :ok} = Groups.remove_member(Scope.current(c.current_user), grant.id, reader.id)

      render(view)
      refute :sys.get_state(view.pid).socket.assigns.comparison
    end

    # What compare stores, whichever revisions the event has.
    defp hold_comparison(view, event) do
      :sys.replace_state(view.pid, fn state ->
        put_in(state.socket.assigns[:comparison], %{event: event, result: :error})
      end)
    end

    # Enough newer events of `event`'s entry to push it off the log's first page.
    defp push_out_of_list(event) do
      later = DateTime.add(event.inserted_at, 60, :second)

      rows =
        for n <- 1..50 do
          %{
            action: :updated,
            source: :admin,
            schema: event.schema,
            entry_id: event.entry_id,
            title: "Newer #{n}",
            inserted_at: DateTime.add(later, n, :second),
            fields: [],
            details: %{}
          }
        end

      Repo.insert_all(Brando.Activity.Event, rows)
    end

    test "an open comparison stays when newer events push its event off the list", c do
      put_test_env(:authorization_mode, :groups)
      {:ok, _} = Migration.run()

      {conn, reader} = Brando.Test.Users.log_in_as(build_conn(), permissions: ~w(brando.activity.read))
      Brando.Test.Users.grant_permissions(reader, ~w(brando.pages.read))
      create_page(c.current_user, "Compared")
      [event] = Repo.all(Brando.Activity.Event)

      {:ok, view, _} = live(conn, "/admin/config/activity")
      hold_comparison(view, event)
      push_out_of_list(event)

      Brando.Authorization.Realtime.broadcast_changed()

      render(view)
      refute Enum.any?(:sys.get_state(view.pid).socket.assigns.events, &(&1.id == event.id))
      assert :sys.get_state(view.pid).socket.assigns.comparison
    end

    test "an open comparison follows the record policy, not the list", c do
      put_test_env(:authorization_mode, :groups)
      viewer = account(:user)
      {:ok, _} = Migration.run()
      scope = Scope.standalone(c.current_user)
      keys = ~w(brando.admin.access brando.activity.read authorization.policy_pages.read)
      {:ok, group} = Groups.create(scope, %{name: "Policy readers"}, keys)
      {:ok, :ok} = Groups.add_member(scope, group.id, viewer.id)

      own = Factory.insert(:page, title: "Own", creator: viewer)
      own = Repo.get!(Brando.AuthorizationTestResources.Page, own.id)
      {:ok, _} = Brando.Activity.record(:updated, own, c.current_user, fields: ["title"])
      [event] = Repo.all(Brando.Activity.Event)

      {:ok, view, _} = live(log_in_user(build_conn(), viewer), "/admin/config/activity")
      hold_comparison(view, event)
      push_out_of_list(event)

      Brando.Authorization.Realtime.broadcast_changed()
      render(view)
      assert :sys.get_state(view.pid).socket.assigns.comparison

      Repo.update_all(from(p in Page, where: p.id == ^own.id), set: [creator_id: c.current_user.id])
      Brando.Authorization.Realtime.broadcast_changed()
      render(view)
      refute :sys.get_state(view.pid).socket.assigns.comparison
    end

    test "an administrator demoted in legacy mode loads nothing more", c do
      put_test_env(:authorization_mode, :legacy)
      create_page(c.current_user, "Listed")
      {:ok, view, _} = live(c.conn, "/admin/config/activity")
      ref = watch(view)

      demote(c.current_user)

      assert_remounted(ref)
      assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = live(c.conn, "/admin/config/activity")
    end
  end

  describe "what the checks cost" do
    setup do
      put_test_env(:authorization_mode, :legacy)
      put_test_env(:tenancy_mode, :none)
      test = self()
      id = "stale-authority-#{System.unique_integer([:positive])}"

      :telemetry.attach(
        id,
        [:brando_integration, :repo, :query],
        fn _, _, %{query: query}, _ -> send(test, {:query, self(), query}) end,
        nil
      )

      on_exit(fn -> :telemetry.detach(id) end)
    end

    defp role_reads(pid) do
      receive do
        {:query, ^pid, query} ->
          if query =~ ~s("users") and query =~ "role" and not (query =~ "avatar"),
            do: 1 + role_reads(pid),
            else: role_reads(pid)
      after
        0 -> 0
      end
    end

    test "a presentation check reads nothing: templates may ask often", c do
      Process.put({BrandoAdmin.Authorization, :legacy_actor}, c.current_user)
      assert BrandoAdmin.Authorization.allowed?(:update, Page)
      Process.delete({BrandoAdmin.Authorization, :legacy_actor})
      assert role_reads(self()) == 0
    end

    test "a LiveView event reads the role once", c do
      {:ok, view, _} = live(c.conn, "/admin/users/sign-in-policy")
      role_reads(view.pid)
      render_click(view, "change", %{"policy" => %{"two_factor" => "everyone"}})
      assert role_reads(view.pid) == 1
    end

    test "a keystroke in an entry form reads the role no more than before", c do
      page = Factory.insert(:page, title: "Before", uri: "stale-keystroke", status: :draft)
      {:ok, view, _} = live(c.conn, "/admin/pages/update/#{page.id}")
      role_reads(view.pid)
      view |> form("#page_form_form", %{"page" => %{"title" => "Typed"}}) |> render_change()
      assert role_reads(view.pid) == 0
    end
  end

  defp site(key) do
    {:ok, site} =
      Registry.create_site(%{
        name: key,
        key: key,
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :dynamic
      })

    site
  end

  # An environment schema with a copy of every tenant table, inside the test's
  # transaction.
  defp environment(site, key, live) do
    {:ok, environment} = Registry.create_environment(site, %{name: key, key: key, live: live})
    prefix = Tenant.prefix(site, environment)
    Repo.query!(~s(CREATE SCHEMA "#{prefix}"))

    "SELECT tablename FROM pg_tables WHERE schemaname = 'public'"
    |> Repo.query!()
    |> Map.fetch!(:rows)
    |> List.flatten()
    |> Enum.reject(&Tenant.SharedTables.member?/1)
    |> Enum.each(fn table ->
      escaped = String.replace(table, "\"", "\"\"")
      Repo.query!(~s|CREATE TABLE "#{prefix}"."#{escaped}" (LIKE public."#{escaped}" INCLUDING ALL)|)
      Repo.query!(~s(INSERT INTO "#{prefix}"."#{escaped}" SELECT * FROM public."#{escaped}"))
    end)

    environment
  end
end

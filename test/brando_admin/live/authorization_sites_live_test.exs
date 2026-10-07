defmodule BrandoAdmin.AuthorizationSitesLiveTest do
  # Group permissions with sites and environments: an editor sees and changes
  # only what their access to each site allows, and an edit in one
  # environment stays there. This was the first test of
  # e2e/playwright/tests/users/authorization-sites.spec.js, which CI ran once
  # with each tenancy mode. The private preview and simultaneous editing tests
  # need a browser and stay there.
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.{Boundary, Catalog, Groups, Migration, Scope}
  alias Brando.Pages.Page
  alias Brando.Tenant
  alias Brando.Tenant.{Access, Cache, Registry}

  defp setup_sites(owner, mode) do
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, mode)
    if mode == :single, do: put_test_env(:site_key, "auth-alpha")
    Cache.clear()
    Boundary.put_scope(nil)

    on_exit(fn ->
      Tenant.put_prefix(nil)
      Boundary.put_scope(nil)
      Cache.clear()
    end)

    # One page, copied into every environment and retitled there.
    page = Factory.insert(:page, title: "Public page", uri: "authorization-sites", status: :draft)

    # As the E2E seed's editor: a superuser by legacy role, taken out of every
    # installation group so that only site access counts.
    editor =
      Factory.insert(:random_user,
        name: "Site editor",
        role: :superuser,
        language: :en,
        config: %Brando.Users.UserConfig{}
      )

    alpha = site("Alpha", "auth-alpha")
    beta = site("Beta", "auth-beta")
    production = environment(alpha, "production", "Production", true)
    staging = environment(alpha, "staging", "Staging", false)
    beta_live = environment(beta, "production", "Production", true)
    {:ok, _} = Migration.run()

    {:ok, installation} = Groups.list(Scope.installation(owner))
    for group <- installation, do: Groups.remove_member(Scope.installation(owner), group.id, editor.id)

    {:ok, _} = Access.grant(editor, alpha, :admin)
    {:ok, _} = Access.grant(editor, beta, :editor)

    {:ok, alpha_group} =
      Groups.create(Scope.site(owner, alpha), %{name: "Alpha managers"}, Catalog.preset_permissions(:admin, :site))

    {:ok, :ok} = Groups.add_member(Scope.site(owner, alpha), alpha_group.id, editor.id)

    outsider =
      Factory.insert(:random_user, name: "Beta colleague", role: :user, language: :en, config: %Brando.Users.UserConfig{})

    {:ok, _} = Access.grant(outsider, beta, :editor)

    if mode == :multi do
      {:ok, beta_group} =
        Groups.create(
          Scope.site(owner, beta),
          %{name: "Beta readers"},
          ~w(brando.admin.access brando.pages.read brando.profile.read brando.profile.update)
        )

      {:ok, :ok} = Groups.add_member(Scope.site(owner, beta), beta_group.id, editor.id)
      {:ok, :ok} = Groups.add_member(Scope.site(owner, beta), beta_group.id, outsider.id)
    end

    for {site, environment, title} <- [
          {alpha, production, "Alpha production page"},
          {alpha, staging, "Alpha staging page"},
          {beta, beta_live, "Beta production page"}
        ] do
      Repo.update_all(from(p in Page, where: p.id == ^page.id), [set: [title: title, status: :draft]],
        prefix: Tenant.prefix(site, environment)
      )
    end

    %{page: page, editor: editor, outsider: outsider}
  end

  defp site(name, key) do
    {:ok, site} =
      Registry.create_site(%{
        name: name,
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
  defp environment(site, key, name, live) do
    {:ok, environment} = Registry.create_environment(site, %{name: name, key: key, live: live})
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

  defp titles do
    for {site_key, env_key} <- [{"auth-alpha", "production"}, {"auth-alpha", "staging"}, {"auth-beta", "production"}],
        into: %{} do
      [title] = Repo.all(from(p in Page, select: p.title), prefix: Tenant.prefix(site_key, env_key))
      {"#{site_key}/#{env_key}", title}
    end
  end

  # Presses a button in the navigation's site and environment switcher: posts
  # its form as the browser would, keeps the session and follows the redirect.
  defp switch_to(conn, html, name, value) do
    form =
      html
      |> Floki.parse_document!()
      |> Floki.find(".tenant-switcher form")
      |> Enum.find(&(Floki.find(&1, "button[name='#{name}'][value='#{value}']") != []))

    assert form, "the switcher offers no #{name}=#{value}"
    [action] = Floki.attribute(form, "action")

    params =
      form
      |> Floki.find("input[type=hidden]")
      |> Map.new(&{hd(Floki.attribute(&1, "name")), hd(Floki.attribute(&1, "value"))})
      |> Map.put(name, value)

    conn = post(conn, action, params)
    {recycle(conn), redirected_to(conn)}
  end

  defp title_value(view) do
    view |> render() |> Floki.parse_document!() |> Floki.find("input[name='page[title]']") |> Floki.attribute("value")
  end

  defp save_title(view, title) do
    view |> form("#page_form_form", %{"page" => %{"title" => title}}) |> render_submit()
    assert_push_event(view, "b:submit", %{}, 2_000)
    view |> form("#page_form_form", %{"page" => %{"title" => title}}) |> render_submit()
  end

  # What both tenancy modes share: the editor's view of Alpha, and an edit in
  # Alpha's staging environment that touches nothing else.
  defp edits_only_staging(data) do
    conn = log_in_user(build_conn(), data.editor)

    {:ok, groups, _html} = live(conn, "/admin/groups")
    render_async(groups)
    assert groups |> element(".authorization-scope") |> render() =~ "Alpha"
    refute has_element?(groups, "[data-user-id='#{data.outsider.id}']")

    path = "/admin/pages/update/#{data.page.id}"
    {:ok, view, html} = live(conn, path)
    render_async(view, 5_000)
    await_selector(view, "#page_form_form input")
    assert title_value(view) == ["Alpha production page"]

    {conn, return_to} = switch_to(conn, html, "environment_key", "staging")
    assert return_to == path
    {view, _html} = live_form(conn, path)
    assert title_value(view) == ["Alpha staging page"]

    save_title(view, "Edited only in staging")
    assert_redirect(view, 3_000)

    assert titles() == %{
             "auth-alpha/staging" => "Edited only in staging",
             "auth-alpha/production" => "Alpha production page",
             "auth-beta/production" => "Beta production page"
           }

    conn
  end

  test "multi-site: roles, membership, reads and writes stay within their site and environment",
       %{current_user: owner} do
    data = setup_sites(owner, :multi)
    conn = edits_only_staging(data)

    {:ok, _view, html} = live(conn, "/admin/pages")
    {conn, _} = switch_to(conn, html, "site_key", "auth-beta")
    {:ok, view, _html} = live(conn, "/admin/pages")
    await_selector(view, "#list-row-#{data.page.id}")

    assert view |> element("#list-row-#{data.page.id}") |> render() =~ "Beta production page"
    refute has_element?(view, "a", "Create page")
    assert has_element?(view, "[data-user-id='#{data.outsider.id}']")

    # A delete the page does not offer, sent anyway, changes nothing.
    render_click(view, "delete_entry", %{"id" => "#{data.page.id}"})
    assert has_element?(view, "#list-row-#{data.page.id}")
    assert titles()["auth-beta/production"] == "Beta production page"

    assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = live(conn, "/admin/pages/update/#{data.page.id}")
    assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = live(conn, "/admin/groups")
  end

  test "single-site: an edit in staging stays in staging", %{current_user: owner} do
    owner |> setup_sites(:single) |> edits_only_staging()
  end
end

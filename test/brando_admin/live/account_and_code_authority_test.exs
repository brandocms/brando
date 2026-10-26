defmodule BrandoAdmin.AccountAndCodeAuthorityTest do
  # Account and code authority in both authorization modes (audit F05): a
  # non-superuser may not take over, disable or delete a superuser, an admin
  # may not grant :superuser, and only superusers write module and container
  # code, which the server compiles and evaluates.
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]
  import Swoosh.TestAssertions

  alias Brando.Authorization.{Boundary, Catalog, Groups, Migration, Scope}
  alias Brando.Tenant
  alias Brando.Tenant.{Access, Cache, Registry}
  alias Brando.Test.Users, as: TestUsers
  alias Brando.Users
  alias Brando.Users.User

  # Evaluated, the expression renders the joined marker; stored or escaped,
  # only its two halves appear.
  @marker "code-authority-marker"
  @heex ~s(<p id="code-authority">{"code-authority-" <> "marker"}</p>)

  defp open_user_form(conn, user) do
    {:ok, view, _} = live(conn, "/admin/users/update/#{user.id}")
    render_async(view, 5_000)
    await_selector(view, "#user_form_form input")
    view
  end

  # Opens the module form and saves HEEx code into it, as the browser would,
  # when the form opens at all.
  defp try_save_module_code(conn, module) do
    case live(conn, "/admin/config/content/modules/update/#{module.id}") do
      {:error, {:redirect, %{to: "/admin/access-denied"}}} ->
        :access_denied

      {:ok, view, _} ->
        params = form_params(render(view), "#module_form")
        render_hook(view, "save", %{"module" => Map.merge(params["module"] || %{}, %{"type" => "heex", "code" => @heex})})

        if Process.alive?(view.pid) and render(view) =~ "confirm_destructive_save",
          do: render_hook(view, "confirm_destructive_save", %{})

        :saved
    end
  end

  describe "legacy mode" do
    test "an editor cannot save HEEx module code", %{conn: _conn} do
      editor = TestUsers.insert_user(role: :editor)
      module = Factory.insert(:module, code: "<p>plain</p>")
      conn = log_in_user(build_conn(), editor)

      assert :access_denied = try_save_module_code(conn, module)

      assert Repo.get!(Brando.Content.Module, module.id).code == "<p>plain</p>"

      assert {:error, :forbidden} = Brando.Content.update_module(module.id, %{code: @heex, type: :heex}, editor)
      assert {:error, :forbidden} = Brando.Content.create_module(%{name: "X", namespace: "x", code: @heex}, editor)
      assert {:error, :forbidden} = Brando.Content.delete_module(module.id, editor)
      assert {:error, :forbidden} = Brando.Content.duplicate_module(module.id, editor)
    end

    test "a superuser saves HEEx module code", %{conn: conn} do
      module = Factory.insert(:module, code: "<p>plain</p>")
      assert :saved = try_save_module_code(conn, module)

      saved = Repo.get!(Brando.Content.Module, module.id)
      assert saved.code == @heex
      assert Brando.Test.Blocks.render_block(saved) =~ @marker
    end

    test "an editor cannot change a superuser's email and reset its password" do
      owner = TestUsers.insert_user(role: :superuser)
      editor = TestUsers.insert_user(role: :editor)
      new_email = "takeover-#{System.unique_integer([:positive])}@example.net"
      conn = log_in_user(build_conn(), editor)

      view = open_user_form(conn, owner)
      view |> form("#user_form_form", %{"user" => %{"email" => new_email}}) |> render_submit()

      assert Repo.get!(User, owner.id).email == owner.email
      :ok = Users.request_password_reset(new_email)
      assert_no_email_sent()

      assert {:error, _} = Users.update_user(owner.id, %{email: new_email}, editor)
      assert Repo.get!(User, owner.id).email == owner.email
    end

    test "only a superuser changes another user's email" do
      admin = TestUsers.insert_user(role: :admin)
      superuser = TestUsers.insert_user(role: :superuser)
      editor = TestUsers.insert_user(role: :editor)

      assert {:error, _} = Users.update_user(editor.id, %{email: "by-admin@example.net"}, admin)
      assert {:ok, %{email: "self@example.net"}} = Users.update_user(admin.id, %{email: "self@example.net"}, admin)
      assert {:ok, %{email: "by-su@example.net"}} = Users.update_user(editor.id, %{email: "by-su@example.net"}, superuser)
    end

    test "an admin cannot raise a user to superuser" do
      admin = TestUsers.insert_user(role: :admin)
      editor = TestUsers.insert_user(role: :editor)
      conn = log_in_user(build_conn(), admin)

      view = open_user_form(conn, editor)
      view |> form("#user_form_form", %{"user" => %{"role" => "superuser"}}) |> render_submit()
      assert Repo.get!(User, editor.id).role == :editor

      assert {:error, _} = Users.update_user(editor.id, %{role: :superuser}, admin)
      assert {:ok, %{role: :admin}} = Users.update_user(editor.id, %{role: :admin}, admin)
    end

    test "an editor cannot disable or delete a superuser" do
      owner = TestUsers.insert_user(role: :superuser)
      editor = TestUsers.insert_user(role: :editor)
      conn = log_in_user(build_conn(), editor)

      {:ok, view, _} = live(conn, "/admin/users")
      render_hook(view, "disable_user", %{"id" => to_string(owner.id)})
      assert Repo.get!(User, owner.id).active

      assert {:error, _} = Users.set_active(owner.id, false, editor)
      assert {:error, _} = Users.delete_user(owner.id, editor)
      assert {:error, _} = Users.delete_user_with_transfer(owner.id, editor.id, editor)
      assert %{active: true, deleted_at: nil} = Repo.get!(User, owner.id)
    end

    test "a changeset built outside the schema cannot raise a role either" do
      admin = TestUsers.insert_user(role: :admin)
      editor = TestUsers.insert_user(role: :editor)

      assert {:error, :forbidden} = Users.update_user(Ecto.Changeset.change(editor, role: :superuser), admin)
      assert Repo.get!(User, editor.id).role == :editor

      # The target as the admin loaded it was an editor; it is a superuser now.
      loaded = TestUsers.insert_user(role: :editor)
      Repo.update!(Ecto.Changeset.change(loaded, role: :superuser))
      assert {:error, :forbidden} = Users.update_user(Ecto.Changeset.change(loaded, role: :admin), admin)
      assert {:error, :forbidden} = Users.update_user(Ecto.Changeset.change(loaded, active: false), admin)
      assert %{role: :superuser, active: true} = Repo.get!(User, loaded.id)

      # The role is read afresh: a superuser demoted while their view is open
      # writes as what they are now.
      demoted = TestUsers.insert_user(role: :superuser)
      Repo.update!(Ecto.Changeset.change(demoted, role: :admin))
      assert {:error, _} = Users.update_user(editor.id, %{role: :superuser}, demoted)
      assert {:error, :forbidden} = Brando.Content.create_module(%{name: "X", namespace: "x", code: @heex}, demoted)
    end

    test "an actor given as an id writes what its stored role allows" do
      user = TestUsers.insert_user(role: :user)
      editor = TestUsers.insert_user(role: :editor)
      page = Factory.insert(:page)

      assert {:error, :forbidden} = Brando.Pages.update_page(page.id, %{title: "By id"}, %{id: user.id})

      assert {:error, :forbidden} =
               Brando.Content.create_module(%{name: "X", namespace: "x", code: @heex}, %{id: editor.id})

      assert {:error, :forbidden} = Brando.Content.create_module(%{name: "X", namespace: "x", code: @heex}, nil)

      assert {:ok, %{title: "By an editor"}} =
               Brando.Pages.update_page(page.id, %{title: "By an editor"}, %{id: editor.id})
    end

    test "a module imported one at a time needs a superuser too" do
      editor = TestUsers.insert_user(role: :editor)
      superuser = TestUsers.insert_user(role: :superuser)
      module = Factory.insert(:module, code: "<p>plain</p>")
      {:ok, [exported]} = Brando.Content.list_modules(%{filter: %{ids: [module.id]}, preload: [:vars, :refs, :children]})

      [decoded] =
        [exported]
        |> Brando.Content.prepare_modules_for_export(superuser.id)
        |> Brando.Content.serialize_modules()
        |> Brando.Content.deserialize_modules()

      assert {:error, :forbidden} = Brando.Content.import_module_with_children(decoded, editor)
      assert {:ok, _} = Brando.Content.import_module_with_children(decoded, superuser)
    end

    test "an admin cannot disable a superuser; a superuser can" do
      owner = TestUsers.insert_user(role: :superuser)
      admin = TestUsers.insert_user(role: :admin)
      superuser = TestUsers.insert_user(role: :superuser)

      assert {:error, _} = Users.set_active(owner.id, false, admin)
      assert {:ok, %{active: false}} = Users.set_active(owner.id, false, superuser)
    end

    test "an editor cannot write containers, import modules or publish shared code" do
      editor = TestUsers.insert_user(role: :editor)
      superuser = TestUsers.insert_user(role: :superuser)
      attrs = %{name: "Section", namespace: "general", help_text: "Help", code: @heex, type: :heex}

      assert {:error, :forbidden} = Brando.Content.create_container(attrs, editor)
      assert {:ok, container} = Brando.Content.create_container(attrs, superuser)
      assert {:error, :forbidden} = Brando.Content.update_container(container.id, %{code: "<p>x</p>"}, editor)
      assert {:error, :forbidden} = Brando.Content.delete_container(container.id, editor)

      module = Factory.insert(:module, code: "<p>plain</p>")
      {:ok, [exported]} = Brando.Content.list_modules(%{filter: %{ids: [module.id]}, preload: [:vars, :refs, :children]})

      encoded =
        [exported] |> Brando.Content.prepare_modules_for_export(superuser.id) |> Brando.Content.serialize_modules()

      decoded = Brando.Content.deserialize_modules(encoded)

      assert {:error, :forbidden} = Brando.Content.import_modules(decoded, editor)
      assert {:ok, [{:ok, _}]} = Brando.Content.import_modules(decoded, superuser)

      shared_attrs = %{
        name: %{"en" => "Shared"},
        namespace: %{"en" => "general"},
        help_text: %{"en" => "Help"},
        class: "s",
        code: "<p>s</p>"
      }

      admin = TestUsers.insert_user(role: :admin)
      assert {:error, :forbidden} = Brando.Content.SharedLibrary.create_shared(:module, shared_attrs, admin)
      assert {:ok, shared} = Brando.Content.SharedLibrary.create_shared(:module, shared_attrs, superuser)

      assert {:error, :forbidden} =
               Brando.Content.SharedLibrary.update_shared(:module, shared.id, %{code: @heex, version_note: "x"}, admin)

      assert {:error, :forbidden} = Brando.Content.SharedLibrary.delete_shared(:module, shared.id, admin)
    end

    test "an editor's module screens offer no writes, and the module form does not open" do
      editor = TestUsers.insert_user(role: :editor)
      module = Factory.insert(:module, code: "<p>plain</p>")
      conn = log_in_user(build_conn(), editor)

      assert {:error, {:redirect, %{to: "/admin/access-denied"}}} =
               live(conn, "/admin/config/content/modules/update/#{module.id}")

      assert {:error, {:redirect, %{to: "/admin/access-denied"}}} = live(conn, "/admin/config/content/containers/create")

      {:ok, view, _} = live(conn, "/admin/config/content/modules")
      await_selector(view, "#list-row-#{module.id}")
      refute has_element?(view, "button[phx-click*='create_module']")
      refute has_element?(view, "#module-transfer-menu button[phx-click*='module-import-modal']")

      # Sent anyway, the events change nothing.
      render_click(view, "create_module", %{})
      render_change(view, "validate_module_import", %{"encoded_modules" => "not decoded"})
      render_click(view, "import_modules", %{})
      assert [_] = Repo.all(Brando.Content.Module)
    end

    test "a superuser's module list offers creating and importing", %{conn: conn} do
      module = Factory.insert(:module, code: "<p>plain</p>")
      {:ok, view, _} = live(conn, "/admin/config/content/modules")
      await_selector(view, "#list-row-#{module.id}")
      assert has_element?(view, "button[phx-click*='create_module']")
      assert has_element?(view, "#module-transfer-menu button[phx-click*='module-import-modal']")
    end

    test "a :user account writes nothing but its own profile" do
      user = TestUsers.insert_user(role: :user)
      page = Factory.insert(:page)

      assert {:error, :forbidden} = Brando.Pages.update_page(page.id, %{title: "By a user"}, user)
      assert {:error, :forbidden} = Brando.Pages.create_page(%{title: "By a user"}, user)
      assert {:error, _} = Users.update_user(TestUsers.insert_user(role: :editor).id, %{name: "Renamed"}, user)
      assert {:ok, %{name: "Myself"}} = Users.update_user(user.id, %{name: "Myself"}, user)
    end
  end

  describe "groups mode, several sites" do
    setup %{current_user: owner} do
      put_test_env(:authorization_mode, :groups)
      put_test_env(:tenancy_mode, :multi)
      Cache.clear()
      Boundary.put_scope(nil)

      on_exit(fn ->
        Tenant.put_prefix(nil)
        Boundary.put_scope(nil)
        Cache.clear()
      end)

      module = Factory.insert(:module, code: "<p>plain</p>")
      alpha = site("Alpha", "code-alpha")
      production = environment(alpha, "production", "Production", true)

      site_admin =
        Factory.insert(:random_user, name: "Site admin", role: :admin, language: :en, config: %Brando.Users.UserConfig{})

      # Migration seeds Alpha's Admin group from the site assignment.
      {:ok, _} = Access.grant(site_admin, alpha, :admin)
      {:ok, _} = Migration.run()

      {:ok, installation} = Groups.list(Scope.installation(owner))
      for group <- installation, do: Groups.remove_member(Scope.installation(owner), group.id, site_admin.id)

      %{
        module: module,
        site_admin: site_admin,
        alpha: alpha,
        production: production,
        prefix: Tenant.prefix(alpha, production)
      }
    end

    test "a site Admin cannot save HEEx module code", %{module: module, site_admin: site_admin, prefix: prefix} = ctx do
      alpha = ctx.alpha
      production = ctx.production
      conn = log_in_user(build_conn(), site_admin)

      assert :access_denied = try_save_module_code(conn, module)

      [saved] = Repo.all(from(m in Brando.Content.Module, where: m.id == ^module.id), prefix: prefix)
      assert saved.code == "<p>plain</p>"

      assert {:error, :forbidden} =
               Brando.Content.update_module(
                 module.id,
                 %{code: @heex, type: :heex},
                 Scope.site(site_admin, alpha, production)
               )
    end

    test "a group grant of module writes grants nothing, and saving the group drops it", %{current_user: owner} = ctx do
      scope = Scope.site(owner, ctx.alpha)
      [update_key] = for p <- Catalog.for_schema(Brando.Content.Module), p.action == :update, do: p.key
      {:ok, groups} = Groups.list(scope)
      admin_group = Enum.find(groups, &(&1.preset == :admin))

      assert {:error, :invalid_permissions} = Groups.create(scope, %{name: "Coders"}, [update_key])

      # As a group may hold it from before it became superuser-only
      Repo.insert!(%Brando.Authorization.Grant{group_id: admin_group.id, permission_key: update_key})
      site_scope = Scope.site(ctx.site_admin, ctx.alpha, ctx.production)
      refute Brando.Authorization.can?(site_scope, :update, Brando.Content.Module)
      assert Brando.Authorization.can?(site_scope, :read, Brando.Content.Module)
      assert Brando.Authorization.can?(Scope.site(owner, ctx.alpha, ctx.production), :update, Brando.Content.Module)

      {:ok, json} = Brando.Authorization.Configuration.export(scope)
      refute json =~ update_key

      {:ok, group} = Groups.get(scope, admin_group.id)
      keys = Enum.map(group.grants, & &1.permission_key) -- [update_key]
      assert {:ok, saved} = Groups.update(scope, group.id, %{}, keys, group.lock_version)
      refute update_key in Enum.map(saved.grants, & &1.permission_key)
    end

    test "no group can hold module or container code writes" do
      for kind <- [:standalone, :site],
          preset <- [:admin, :editor],
          key <- Catalog.preset_permissions(preset, kind) do
        refute Catalog.fetch(key).subject in [Brando.Content.Module, Brando.Content.Container] and
                 Catalog.fetch(key).action not in [:read, :export],
               "#{preset} preset grants #{key}"
      end
    end
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
end

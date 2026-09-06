defmodule Brando.Authorization.GroupsTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Authorization
  alias Brando.Authorization.{Catalog, Engine, Group, Groups, Migration, Scope}
  alias Brando.Factory
  alias Brando.Pages.Page
  alias Brando.Tenant.Registry

  setup do
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, :none)
    owner = Factory.insert(:random_user, role: :superuser)
    editor = Factory.insert(:random_user, role: :editor)
    user = Factory.insert(:random_user, role: :user)
    {:ok, _} = Migration.run()
    %{owner: owner, editor: editor, user: user, scope: Scope.standalone(owner)}
  end

  test "the default role migration preserves intended content rights without making User an editor", c do
    assert Authorization.can?(c.owner, :delete, Page)
    assert Authorization.can?(c.editor, :update, Page)
    assert Authorization.can?(c.editor, :publish, Page)
    refute Authorization.can?(c.editor, :update, :groups)
    refute Authorization.can?(c.user, :access, :backend)
    refute Authorization.can?(c.user, :read, Page)
  end

  test "unknown permissions and invalid actors fail with predictable results", c do
    for actor <- [nil, %Brando.Users.User{}, %{id: -1}, c.user] do
      refute Authorization.can?(actor, :read, Page)
      assert {:error, :forbidden} = Authorization.authorize(actor, :read, Page)
    end

    refute Authorization.can?(c.owner, :unregistered, Page)
    refute Authorization.can?(c.owner, :read, "Page")
    assert %{reason: :unknown_permission} = Authorization.explain(c.owner, :unregistered, Page)
  end

  test "custom groups start empty; names and legacy roles never grant authority", c do
    {:ok, group} = Groups.create(c.scope, %{name: "Superuser"})
    assert group.preset == nil
    assert group.grants == []
    assert {:ok, :ok} = Groups.add_member(c.scope, group.id, c.user.id)
    refute Engine.superuser?(c.user)
    refute Authorization.can?(c.user, :read, Page)
    Repo.update!(Ecto.Changeset.change(c.user, role: :superuser))
    refute Engine.superuser?(c.user)
  end

  test "permissions combine across groups and removing one grant leaves other grants intact", c do
    keys = ["brando.admin.access", "brando.pages.read", "brando.pages.update"]
    {:ok, editing} = Groups.create(c.scope, %{name: "Editing"}, keys)
    {:ok, publishing} = Groups.create(c.scope, %{name: "Publishing"}, ["brando.pages.publish"])
    {:ok, :ok} = Groups.add_member(c.scope, editing.id, c.user.id)
    {:ok, :ok} = Groups.add_member(c.scope, publishing.id, c.user.id)
    assert Authorization.can?(c.user, :update, Page)
    assert Authorization.can?(c.user, :publish, Page)
    assert %{groups: [%{name: "Publishing"}]} = Authorization.explain(c.user, :publish, Page)
    {:ok, :ok} = Groups.remove_member(c.scope, publishing.id, c.user.id)
    assert Authorization.can?(c.user, :update, Page)
    refute Authorization.can?(c.user, :publish, Page)
  end

  test "updates reject unknown grants, wrong-scope grants and stale forms without changing saved rights", c do
    {:ok, group} = Groups.create(c.scope, %{name: "Reviewed"}, ["brando.admin.access"])
    assert {:error, :invalid_permissions} = Groups.update(c.scope, group.id, %{name: "Wrong"}, ["invented.admin"], 1)
    assert {:error, :invalid_permissions} = Groups.update(c.scope, group.id, %{}, ["brando.sites.delete"], 1)
    {:ok, saved} = Groups.update(c.scope, group.id, %{name: "Saved"}, ["brando.admin.access", "brando.pages.read"], 1)
    assert saved.lock_version == 2
    assert {:error, :stale} = Groups.update(c.scope, group.id, %{name: "Stale"}, [], 1)
    assert {:ok, %{name: "Saved", grants: grants}} = Groups.get(c.scope, group.id)
    assert length(grants) == 2
  end

  test "grant edits and account deactivation revoke authority even when the caller holds old structs", c do
    snapshot = Authorization.snapshot(c.editor)
    assert Authorization.can?(snapshot, :update, Page)
    Repo.update!(Ecto.Changeset.change(c.editor, active: false))
    refute Authorization.can?(c.editor, :update, Page)
    assert {:error, :forbidden} = Authorization.authorize(snapshot, :update, Page)
    assert %{reason: :inactive_account} = Authorization.explain(c.editor, :read, Page)
  end

  test "backend access is independent from a content grant", c do
    {:ok, group} = Groups.create(c.scope, %{name: "No access"}, ["brando.pages.read"])
    {:ok, :ok} = Groups.add_member(c.scope, group.id, c.user.id)
    assert %{reason: :backend_access_required} = Authorization.explain(c.user, :read, Page)
  end

  test "delegated administrators cannot add rights they do not have to their own group", c do
    keys = ["brando.admin.access", "brando.groups.read", "brando.groups.update", "brando.groups.assign"]
    {:ok, group} = Groups.create(c.scope, %{name: "Delegated"}, keys)
    {:ok, :ok} = Groups.add_member(c.scope, group.id, c.user.id)
    scope = Scope.standalone(c.user)
    assert {:error, :not_delegable} = Groups.update(scope, group.id, %{}, keys ++ ["brando.pages.delete"], 1)
    refute Authorization.can?(c.user, :delete, Page)
    assert {:error, :forbidden} = Groups.create(scope, %{name: "Escalation"})
  end

  test "delegated managers can save details while unheld grants remain locked", c do
    manager_keys = ~w(brando.admin.access brando.groups.read brando.groups.update brando.pages.read)
    {:ok, manager} = Groups.create(c.scope, %{name: "Limited manager"}, manager_keys)
    {:ok, :ok} = Groups.add_member(c.scope, manager.id, c.user.id)
    keys = ~w(brando.admin.access brando.pages.read brando.pages.delete)
    {:ok, target} = Groups.create(c.scope, %{name: "Wider group"}, keys)
    scope = Scope.standalone(c.user)
    assert {:ok, saved} = Groups.update(scope, target.id, %{description: "Updated details"}, keys, 1)
    assert saved.description == "Updated details"
    assert {:error, :not_delegable} = Groups.update(scope, target.id, %{}, keys -- ["brando.pages.delete"], 2)
    assert {:error, :not_delegable} = Groups.update(scope, target.id, %{}, keys ++ ["brando.pages.publish"], 2)
    assert {:ok, _} = Groups.update(scope, target.id, %{}, keys -- ["brando.pages.read"], 2)
  end

  test "the last active Superuser cannot be removed and custom groups cannot manufacture system authority", c do
    scope = Scope.installation(c.owner)
    group = Repo.one!(from(g in Group, where: g.preset == :superuser))
    assert {:error, :protected_group} = Groups.update(scope, group.id, %{name: "Changed"}, [], 1)
    assert {:error, :protected_group} = Groups.delete(scope, group.id, 1)
    assert {:error, :last_superuser} = Groups.remove_member(scope, group.id, c.owner.id)
    assert {:ok, :ok} = Groups.add_member(scope, group.id, c.user.id)
    assert {:ok, :ok} = Groups.remove_member(scope, group.id, c.owner.id)
    refute Engine.superuser?(c.owner)
    assert Engine.superuser?(c.user)
  end

  test "all security tables stay public and are excluded from content cloning" do
    for table <-
          ~w(authorization_groups authorization_group_permissions authorization_user_groups authorization_audit_events) do
      assert Brando.Tenant.SharedTables.member?(table)
    end
  end

  test "editing a published entry requires publish even when the status does not change", c do
    {:ok, group} =
      Groups.create(c.scope, %{name: "Authors"}, ["brando.admin.access", "brando.pages.read", "brando.pages.update"])

    {:ok, :ok} = Groups.add_member(c.scope, group.id, c.user.id)
    published = Factory.insert(:page, status: :published)
    draft = Factory.insert(:page, status: :draft)

    assert {:error, :forbidden} =
             Engine.authorize_change(c.user, :update, Ecto.Changeset.change(published, title: "Visible change"))

    assert :ok = Engine.authorize_change(c.user, :update, Ecto.Changeset.change(draft, title: "Draft change"))

    assert {:error, :forbidden} =
             Engine.authorize_change(c.user, :update, Ecto.Changeset.change(draft, status: :published))
  end

  test "a site's Admin and another site's Editor do not share privileges", c do
    put_test_env(:tenancy_mode, :multi)
    acme = site("Acme", "auth-acme")
    beta = site("Beta", "auth-beta")
    Brando.Tenant.Access.grant(c.user, acme, :admin)
    Brando.Tenant.Access.grant(c.user, beta, :editor)
    {:ok, _} = Migration.run()
    acme_scope = Scope.site(c.user, acme)
    beta_scope = Scope.site(c.user, beta)
    assert Authorization.can?(acme_scope, :update, :groups)
    refute Authorization.can?(beta_scope, :update, :groups)
    assert Authorization.can?(beta_scope, :update, Page)
    refute Authorization.can?(Scope.installation(c.user), :update, :sites)
    refute Authorization.can?(Scope.standalone(c.user), :update, Page)
    {:ok, acme_groups} = Groups.list(Scope.site(c.owner, acme))
    assert {:error, :not_found} = Groups.get(Scope.site(c.owner, beta), hd(acme_groups).id)
  end

  test "an unassigned site, suspended site and forged environment remain inaccessible", c do
    put_test_env(:tenancy_mode, :multi)
    acme = site("Acme", "scope-acme")
    beta = site("Beta", "scope-beta")
    Brando.Tenant.Access.grant(c.user, acme, :admin)
    {:ok, _} = Migration.run()
    refute Authorization.can?(Scope.site(c.user, beta), :read, Page)
    {:ok, suspended} = Registry.update_site(acme, %{status: :suspended})
    refute Authorization.can?(Scope.site(c.owner, suspended), :read, Page)

    env =
      Repo.insert!(%Brando.Environments.Environment{site_id: beta.id, name: "Production", key: "production", live: true})

    forged = Scope.site(c.owner, acme, env)
    refute Authorization.can?(forged, :read, Page)
  end

  test "single-site mode only accepts the configured site", c do
    put_test_env(:tenancy_mode, :single)
    acme = site("Acme", "single-acme")
    beta = site("Beta", "single-beta")
    put_test_env(:site_key, acme.key)
    {:ok, _} = Migration.run()
    assert Authorization.can?(Scope.site(c.editor, acme), :update, Page)
    refute Authorization.can?(Scope.site(c.owner, beta), :update, Page)
  end

  test "query scoping uses the authorized environment and denies a foreign loaded record", c do
    put_test_env(:tenancy_mode, :multi)
    acme = site("Acme", "query-acme")
    beta = site("Beta", "query-beta")

    env_a =
      Repo.insert!(%Brando.Environments.Environment{site_id: acme.id, name: "Production", key: "production", live: true})

    env_b =
      Repo.insert!(%Brando.Environments.Environment{site_id: beta.id, name: "Production", key: "production", live: true})

    scope = Scope.site(c.owner, acme, env_a)
    query = Authorization.scope(scope, :read, Page)
    assert query.prefix == "tenant_query-acme_production"
    foreign = Ecto.put_meta(%Page{id: 99}, state: :loaded, prefix: Brando.Tenant.prefix(beta, env_b))
    refute Authorization.can?(scope, :update, foreign)
    local = Ecto.put_meta(%Page{id: 99}, state: :loaded, prefix: scope.prefix)
    assert Authorization.can?(scope, :update, local)
  end

  test "repeat migration preserves edits to preset permission sets", c do
    {:ok, groups} = Groups.list(c.scope)
    editor = Enum.find(groups, &(&1.preset == :editor))

    {:ok, _} =
      Groups.update(c.scope, editor.id, %{name: "Limited editors"}, ["brando.admin.access", "brando.pages.read"], 1)

    {:ok, _} = Migration.run()
    refute Authorization.can?(c.editor, :update, Page)
    assert Authorization.can?(c.editor, :read, Page)
  end

  test "catalog exposes real Blueprint actions and never treats unknown keys as grants" do
    assert %{key: "brando.pages.update", label: label} = Catalog.get(:update, Page)
    assert is_binary(label)
    assert Catalog.get(:publish, Page)
    assert Catalog.fetch("not.a.permission") == nil
    assert Catalog.schema("Unregistered.Schema") == nil
  end

  test "re-running migration never resurrects a revoked membership", c do
    {:ok, groups} = Groups.list(c.scope)
    editor = Enum.find(groups, &(&1.preset == :editor))
    {:ok, :ok} = Groups.remove_member(c.scope, editor.id, c.editor.id)
    {:ok, _} = Migration.run()
    refute Authorization.can?(c.editor, :access, :backend)
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
end

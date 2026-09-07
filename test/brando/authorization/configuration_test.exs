defmodule Brando.Authorization.ConfigurationTest do
  use Brando.ConnCase
  alias Brando.Authorization.{Administration, AuditEvent, Configuration, Engine, Group, Groups, Migration, Scope}
  alias Brando.Factory

  setup do
    put_test_env(:authorization_mode, :legacy)
    put_test_env(:tenancy_mode, :none)
    owner = Factory.insert(:random_user, role: :superuser)
    %{owner: owner, scope: Scope.standalone(owner)}
  end

  test "only fresh active legacy superusers can prepare groups, without enabling the resolver", c do
    admin = Factory.insert(:random_user, role: :admin)
    denied = Scope.standalone(admin)
    assert {:error, :forbidden} = Configuration.report(denied)
    assert {:error, :forbidden} = Configuration.backfill(denied)
    assert {:error, :forbidden} = Configuration.export(denied)
    assert {:error, :forbidden} = Groups.create(denied, %{name: "Unauthorized"})
    assert {:ok, _} = Configuration.backfill(c.scope)
    refute Engine.enabled?()
    assert {:ok, group} = Groups.create(c.scope, %{name: "Prepared"}, ["brando.admin.access"])
    assert {:ok, _} = Groups.update(c.scope, group.id, %{name: "Reviewed"}, [], group.lock_version)
    Repo.update!(Ecto.Changeset.change(c.owner, active: false))
    refute Administration.superuser?(c.scope)
    assert {:error, :forbidden} = Configuration.backfill(c.scope)
    assert {:error, :forbidden} = Groups.update(c.scope, group.id, %{}, [], 2)
  end

  test "groups mode uses protected membership, never a leftover legacy role", c do
    put_test_env(:authorization_mode, :groups)
    assert {:error, :forbidden} = Configuration.backfill(c.scope)
    assert {:ok, _} = Migration.run()
    assert {:ok, _} = Configuration.report(c.scope)
    Repo.update!(Ecto.Changeset.change(c.owner, role: :user))
    assert {:ok, _} = Configuration.export(c.scope)
  end

  test "a versioned export round-trips without database IDs, accounts or protected grants", c do
    assert {:ok, _} = Configuration.backfill(c.scope)
    {:ok, json} = Configuration.export(c.scope)
    decoded = Jason.decode!(json)
    assert Map.keys(decoded) |> Enum.sort() == ["format", "groups", "scope", "version"]
    assert decoded["format"] == "brando.authorization"
    assert decoded["scope"] == "standalone"
    assert Enum.map(decoded["groups"], & &1["key"]) == ["admin", "editor", "user"]

    assert Enum.all?(
             decoded["groups"],
             &(Map.keys(&1) |> Enum.sort() == ["description", "key", "name", "permissions", "preset"])
           )

    assert {:ok, preview} = Configuration.preview(c.scope, json)
    assert preview.unchanged == 3
    assert {:ok, %{created: 0, updated: 0}} = Configuration.apply(c.scope, json, preview.revision)
    assert {:ok, ^json} = Configuration.export(c.scope)
    assert {:ok, installation_json} = Configuration.export(Scope.installation(c.owner))
    assert Jason.decode!(installation_json)["groups"] == []
  end

  test "reviewed imports replace grants, preserve memberships and other groups, and audit atomically", c do
    member = Factory.insert(:random_user, role: :editor)
    {:ok, group} = Groups.create(c.scope, %{name: "Old name"}, ["brando.admin.access", "brando.pages.update"])
    {:ok, kept} = Groups.create(c.scope, %{name: "Keep me"}, ["brando.pages.read"])
    {:ok, :ok} = Groups.add_member(c.scope, group.id, member.id)

    json =
      document([entry(group.key, "Reviewed", ["brando.admin.access", "brando.pages.read"]), entry("news", "News", [])])

    assert {:ok, preview} = Configuration.preview(c.scope, json)
    assert %{created: 1, updated: 1, members: 1} = preview
    assert {:ok, %{name: "Old name"}} = Groups.get(c.scope, group.id)
    change = Enum.find(preview.changes, &(&1.action == :update))
    assert change.added == ["brando.pages.read"]
    assert change.removed == ["brando.pages.update"]
    assert {:ok, %{created: 1, updated: 1}} = Configuration.apply(c.scope, json, preview.revision)
    assert {:ok, %{name: "Reviewed", memberships: [membership], lock_version: 2}} = Groups.get(c.scope, group.id)
    assert membership.user_id == member.id
    assert {:ok, %{name: "Keep me"}} = Groups.get(c.scope, kept.id)

    assert Repo.aggregate(
             from(e in AuditEvent, where: e.action == "group.imported" and e.actor_id == ^c.owner.id),
             :count
           ) == 2

    assert {:ok, preview} = Configuration.preview(c.scope, json)
    assert %{unchanged: 2, updated: 0} = preview
  end

  test "importing a tuned preset before backfill preserves its grants and removed memberships", c do
    editor = Factory.insert(:random_user, role: :editor)

    json =
      document([
        Map.put(entry("editor", "Editorial team", ["brando.admin.access", "brando.pages.read"]), "preset", "editor")
      ])

    {:ok, preview} = Configuration.preview(c.scope, json)
    assert {:ok, _} = Configuration.apply(c.scope, json, preview.revision)
    assert {:ok, _} = Configuration.backfill(c.scope)
    group = Repo.get_by!(Group, key: "editor", scope_kind: :standalone)
    {:ok, saved} = Groups.get(c.scope, group.id)
    assert Enum.sort(Enum.map(saved.grants, & &1.permission_key)) == ["brando.admin.access", "brando.pages.read"]
    assert Enum.any?(saved.memberships, &(&1.user_id == editor.id))
    assert {:ok, :ok} = Groups.remove_member(c.scope, group.id, editor.id)
    assert {:ok, _} = Configuration.backfill(c.scope)
    {:ok, saved} = Groups.get(c.scope, group.id)
    refute Enum.any?(saved.memberships, &(&1.user_id == editor.id))
  end

  test "concurrent group or membership changes invalidate a preview", c do
    {:ok, group} = Groups.create(c.scope, %{name: "Original"}, [])
    json = document([entry(group.key, "Import", [])])
    {:ok, preview} = Configuration.preview(c.scope, json)
    {:ok, _} = Groups.update(c.scope, group.id, %{name: "Concurrent"}, [], group.lock_version)
    assert {:error, :stale} = Configuration.apply(c.scope, json, preview.revision)
    {:ok, preview} = Configuration.preview(c.scope, json)
    {:ok, :ok} = Groups.add_member(c.scope, group.id, c.owner.id)
    assert {:error, :stale} = Configuration.apply(c.scope, json, preview.revision)
    assert {:ok, %{name: "Concurrent"}} = Groups.get(c.scope, group.id)
  end

  test "malformed, protected, duplicate and unsupported imports fail without partial changes", c do
    valid = entry("valid", "Valid", [])

    invalid_entries = [
      entry("bad", "Unknown grant", ["unregistered.permission"]),
      entry("bad", "Wrong scope", ["brando.sites.delete"]),
      entry("superuser", "Protected", []),
      Map.put(entry("bad", "Forged", []), "preset", "superuser"),
      Map.put(valid, "memberships", [%{"user_id" => c.owner.id}]),
      Map.put(valid, "id", 123),
      Map.put(valid, "description", %{}),
      Map.put(valid, "name", "  "),
      Map.put(valid, "key", "bad key"),
      Map.put(valid, "permissions", %{})
    ]

    for invalid <- invalid_entries do
      json = document([valid, invalid])
      assert {:error, {:invalid_config, _}} = Configuration.preview(c.scope, json)
      assert {:error, {:invalid_config, _}} = Configuration.apply(c.scope, json, "forged")
      assert Repo.all(Group) == []
    end

    for json <- [
          "invalid",
          "null",
          "[]",
          document([valid, valid]),
          String.duplicate(" ", Configuration.max_bytes() + 1),
          document([valid], "site")
        ] do
      assert {:error, {:invalid_config, _}} = Configuration.preview(c.scope, json)
    end
  end

  test "authority is reloaded between preview and apply", c do
    json = document([entry("reviewed", "Reviewed", [])])
    {:ok, preview} = Configuration.preview(c.scope, json)
    Repo.update!(Ecto.Changeset.change(c.owner, role: :admin))
    assert {:error, :forbidden} = Configuration.apply(c.scope, json, preview.revision)
    assert Repo.all(Group) == []
  end

  test "site exports use portable keys and import only into the selected active site", c do
    put_test_env(:tenancy_mode, :multi)

    sites =
      Enum.map([{"Source", "transfer-source"}, {"Target", "transfer-target"}], fn {name, key} ->
        {:ok, site} =
          Brando.Tenant.Registry.create_site(%{
            name: name,
            key: key,
            languages: ["en"],
            default_language: "en",
            status: :active,
            delivery_mode: :dynamic
          })

        site
      end)

    [source, target] = sites
    source_scope = Scope.site(c.owner, source)
    target_scope = Scope.site(c.owner, target)
    {:ok, original} = Groups.create(source_scope, %{name: "Portable"}, ["brando.admin.access"])
    {:ok, :ok} = Groups.add_member(source_scope, original.id, c.owner.id)
    {:ok, json} = Configuration.export(source_scope)
    {:ok, preview} = Configuration.preview(target_scope, json)
    assert preview.created == 1
    assert {:ok, _} = Configuration.apply(target_scope, json, preview.revision)
    {:ok, [copied]} = Groups.list(target_scope)
    assert copied.key == original.key
    assert copied.id != original.id
    assert copied.site_id == target.id
    assert copied.memberships == []
    assert {:ok, %{memberships: [_]}} = Groups.get(source_scope, original.id)
    {:ok, _} = Brando.Tenant.Registry.update_site(target, %{status: :suspended})
    assert {:error, :forbidden} = Configuration.export(target_scope)
    assert {:error, :forbidden} = Configuration.apply(target_scope, json, preview.revision)
    on_exit(fn -> Brando.Tenant.Cache.clear() end)
  end

  defmodule LegacyRules do
    use Brando.Authorization
    types([{"Page", Brando.Pages.Page}])

    rules :admin do
      can :manage, :all
      cannot :view, "MenuItem", when: %{to: %{name: "modules"}}
      can :update, "Page", when: %{creator_id: 42}
    end
  end

  test "the report inspects actual conditional and inverted application rules" do
    report = Migration.legacy_rules_report(LegacyRules)
    assert report.available
    assert report.review_count == 3
    admin = Enum.find(report.roles, &(&1.role == :admin))
    assert Enum.any?(admin.rules, &(&1.effect == "Cannot" and &1.conditional and &1.conditions =~ "modules"))
    assert Enum.any?(admin.rules, &(&1.subject == "Brando.Pages.Page" and &1.conditions =~ "42"))
    assert Enum.find(report.roles, &(&1.role == :editor)).error
    refute Migration.legacy_rules_report(__MODULE__.Missing).available
  end

  defp entry(key, name, permissions),
    do: %{"key" => key, "name" => name, "permissions" => permissions, "description" => nil, "preset" => nil}

  defp document(entries, scope \\ "standalone"),
    do: Jason.encode!(%{"format" => "brando.authorization", "version" => 1, "scope" => scope, "groups" => entries})
end

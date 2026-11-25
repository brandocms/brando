defmodule Brando.Migrations.Brando249GrantPublishingConfigureTest do
  # Runs the upgrade template inside the sandbox transaction, over groups
  # granted before building, deploying and scheduling stopped including
  # configuring publishing (#3985).
  use Brando.ConnCase

  import Brando.MigrationTemplates
  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.{Grant, Groups, Migration, Scope}
  alias Brando.Factory
  alias Brando.Tenant.{Access, Cache, Registry}

  @template "brando_249_grant_publishing_configure.exs"
  @configure "brando.publishing.configure"

  setup do
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, :multi)
    Cache.clear()
    on_exit(&Cache.clear/0)

    {:ok, site} =
      Registry.create_site(%{
        name: "Configure",
        key: "configure-#{System.unique_integer([:positive])}",
        languages: ["en"],
        default_language: "en",
        status: :active,
        delivery_mode: :static
      })

    {:ok, _environment} = Registry.create_environment(site, %{name: "Production", key: "production", live: true})
    superuser = Factory.insert(:random_user, role: :superuser)
    {:ok, _} = Migration.run()
    %{site: Registry.get_site(site.id), scope: Scope.site(superuser, Registry.get_site(site.id))}
  end

  # A group as it was before the change: its grants with no configure
  defp group!(c, actions) do
    {:ok, group} =
      Groups.create(c.scope, %{name: "Group #{System.unique_integer([:positive])}"}, [
        "brando.admin.access" | Enum.map(actions, &"brando.publishing.#{&1}")
      ])

    group.id
  end

  defp grants(group_id),
    do: Repo.all(from(g in Grant, where: g.group_id == ^group_id, select: g.permission_key)) |> Enum.sort()

  defp configure?(group_id), do: @configure in grants(group_id)

  defp forget_configure,
    do: Repo.delete_all(from(g in Grant, where: g.permission_key == @configure))

  test "gives configure to every group that may build, deploy or schedule, once, and to no other", c do
    build = group!(c, [:read, :build])
    schedule = group!(c, [:schedule])
    deploy = group!(c, [:read, :deploy])
    read = group!(c, [:read])
    none = group!(c, [])
    forget_configure()

    version = up(@template)
    up(@template)

    for group <- [build, schedule, deploy], do: assert(Enum.count(grants(group), &(&1 == @configure)) == 1)
    refute configure?(read)
    refute configure?(none)
    assert grants(build) == ["brando.admin.access", "brando.publishing.build", @configure, "brando.publishing.read"]

    # An administrator's grant made since stays: nothing tells it apart
    down(@template, version)
    assert configure?(build)
  end

  # Admin had build, deploy and schedule from its preset; a new site's
  # Editor has build and deploy, and configures nothing until it ran
  test "a migrated site's Admin may configure and grant it; a publisher without it may not grant it", c do
    forget_configure()
    admin = Factory.insert(:random_user, role: :editor)
    {:ok, _} = Access.grant(admin, c.site, :admin)
    {:ok, _} = Migration.run()
    refute Brando.SSG.Builds.can_configure?(admin, c.site)

    up(@template)
    assert Brando.SSG.Builds.can_configure?(admin, c.site)

    manager = Factory.insert(:random_user, role: :editor)

    {:ok, managers} =
      Groups.create(c.scope, %{name: "Publishing managers"}, [
        "brando.admin.access",
        "brando.groups.read",
        "brando.groups.update",
        "brando.publishing.read",
        "brando.publishing.build",
        "brando.publishing.deploy"
      ])

    {:ok, :ok} = Groups.add_member(c.scope, managers.id, manager.id)
    target = group!(c, [:read, :build])
    keys = grants(target)
    assert {:error, :not_delegable} = Groups.update(Scope.site(manager, c.site), target, %{}, [@configure | keys], 1)
    assert {:ok, _} = Groups.update(Scope.site(admin, c.site), target, %{}, [@configure | keys], 1)
    assert configure?(target)
  end
end

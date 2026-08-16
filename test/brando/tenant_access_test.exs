defmodule Brando.TenantAccessTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Tenant.Access
  alias Brando.Tenant.Cache
  alias Brando.Tenant.Registry

  setup do
    put_test_env(:tenancy_mode, :multi)
    Cache.clear()

    on_exit(&Cache.clear/0)

    {:ok, acme} = create_site("Acme", "access-acme")
    {:ok, beta} = create_site("Beta", "access-beta")
    {:ok, suspended} = create_site("Suspended", "access-suspended", :suspended)

    superuser = Brando.Factory.insert(:random_user, role: :superuser)
    admin = Brando.Factory.insert(:random_user, role: :admin)
    editor = Brando.Factory.insert(:random_user, role: :editor)

    %{admin: admin, acme: acme, beta: beta, editor: editor, superuser: superuser, suspended: suspended}
  end

  test "superusers bypass assignments for active sites", context do
    assert Enum.map(Access.list_sites(context.superuser), & &1.id) == [context.acme.id, context.beta.id]
    assert Access.role_for(context.superuser, context.acme) == :superuser
    assert Access.can_manage?(context.superuser, context.beta)
    refute Access.can_access?(context.superuser, context.suspended)
  end

  test "regular users see only assigned active sites with their per-site role", context do
    assert {:ok, _assignment} = Access.grant(context.admin, context.acme, :admin)
    assert {:ok, _assignment} = Access.grant(context.admin, context.beta, :editor)
    assert {:ok, _assignment} = Access.grant(context.admin, context.suspended, :admin)

    assert Enum.map(Access.list_sites(context.admin), & &1.id) == [context.acme.id, context.beta.id]
    assert Access.role_for(context.admin, context.acme) == :admin
    assert Access.role_for(context.admin, context.beta) == :editor
    assert Access.can_manage?(context.admin, context.acme)
    refute Access.can_manage?(context.admin, context.beta)
    refute Access.can_access?(context.admin, context.suspended)
  end

  test "grant updates an assignment and revoke removes access", context do
    assert {:ok, assignment} = Access.grant(context.editor, context.acme, :editor)
    assert assignment.role == :editor

    assert {:ok, updated} = Access.grant(context.editor, context.acme, :admin)
    assert updated.id == assignment.id
    assert updated.role == :admin

    assert :ok = Access.revoke(context.editor, context.acme)
    assert :ok = Access.revoke(context.editor, context.acme)
    refute Access.can_access?(context.editor, context.acme)
  end

  defp create_site(name, key, status \\ :active) do
    Registry.create_site(%{
      name: name,
      key: key,
      languages: ["en"],
      default_language: "en",
      status: status,
      delivery_mode: :dynamic
    })
  end
end

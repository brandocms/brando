defmodule Brando.Authorization.ConcurrencyTest do
  use ExUnit.Case, async: false
  import Brando.Test.Support
  import Ecto.Query, only: [from: 2]
  alias Brando.Authorization.{AuditEvent, Group, Groups, Membership, Migration, Scope}
  alias BrandoIntegration.Repo
  alias Ecto.Adapters.SQL.Sandbox

  test "simultaneous Superuser removals on independent connections preserve an active administrator" do
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, :none)

    {a, b, group, created_groups} =
      Sandbox.unboxed_run(Repo, fn ->
        before = Repo.all(from(g in Group, select: g.id))
        a = Brando.Factory.insert(:random_user, role: :superuser, avatar: nil)
        b = Brando.Factory.insert(:random_user, role: :superuser, avatar: nil)
        {:ok, _} = Migration.run()
        group = Repo.one!(from(g in Group, where: g.preset == :superuser))
        after_ids = Repo.all(from(g in Group, select: g.id))
        {a, b, group, after_ids -- before}
      end)

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        user_ids = [a.id, b.id]
        Repo.delete_all(from(e in AuditEvent, where: e.actor_id in ^user_ids or e.group_id in ^created_groups))
        Repo.delete_all(from(m in Membership, where: m.user_id in ^user_ids))
        Repo.delete_all(from(g in Group, where: g.id in ^created_groups))
        Repo.delete_all(from(u in Brando.Users.User, where: u.id in ^user_ids))
        Repo.delete_all(from(m in "authorization_legacy_mappings", where: m.source_id in ^user_ids))
      end)
    end)

    parent = self()

    tasks =
      Enum.map([{a, b}, {b, a}], fn {actor, target} ->
        Task.async(fn ->
          Sandbox.unboxed_run(Repo, fn ->
            send(parent, {:ready, self()})

            receive do
              :go -> :ok
            after
              5_000 -> raise "concurrency barrier timed out"
            end

            Groups.remove_member(Scope.installation(actor), group.id, target.id)
          end)
        end)
      end)

    assert_receive {:ready, first}, 5_000
    assert_receive {:ready, second}, 5_000
    send(first, :go)
    send(second, :go)
    results = Enum.map(tasks, &Task.await(&1, 10_000))
    assert Enum.count(results, &(&1 == {:ok, :ok})) == 1
    assert Enum.count(results, &match?({:error, _}, &1)) == 1

    remaining =
      Sandbox.unboxed_run(Repo, fn ->
        Repo.aggregate(from(m in Membership, where: m.group_id == ^group.id), :count)
      end)

    assert remaining == 1
  end
end

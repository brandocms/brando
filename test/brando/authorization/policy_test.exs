defmodule Brando.Authorization.PolicyTest do
  use Brando.ConnCase
  alias Brando.Factory
  alias Brando.Authorization.{Boundary, Engine, Migration, Scope}
  alias Brando.AuthorizationTestResources.{Page, UnscopedPage}

  setup do
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, :none)
    owner = Factory.insert(:random_user, role: :superuser)
    other = Factory.insert(:random_user)
    {:ok, _} = Migration.run()
    foreign = Factory.insert(:page, creator: other)
    own = Factory.insert(:page, title: "Exportable", creator: owner)
    hidden_export = Factory.insert(:page, title: "Internal", creator: owner)
    %{scope: Scope.standalone(owner), own: own, foreign: foreign, hidden_export: hidden_export}
  end

  test "ownership is applied before pagination and cannot be overridden by Superuser", c do
    query = from(p in Engine.scope(c.scope, :read, Page), order_by: p.id, limit: 1)
    assert [%{id: id}] = Repo.all(query)
    assert id == c.own.id
    refute Engine.can?(c.scope, :update, Repo.get!(Page, c.foreign.id))
  end

  test "both original and proposed ownership must satisfy policy", c do
    own = Repo.get!(Page, c.own.id)
    foreign = Repo.get!(Page, c.foreign.id)
    assert :ok = Engine.authorize_change(c.scope, :update, Ecto.Changeset.change(own, title: "Allowed"))

    assert {:error, :forbidden} =
             Engine.authorize_change(c.scope, :update, Ecto.Changeset.change(own, creator_id: foreign.creator_id))

    assert {:error, :forbidden} =
             Engine.authorize_change(c.scope, :update, Ecto.Changeset.change(foreign, creator_id: own.creator_id))
  end

  test "export uses its own query policy and restores normal reads afterwards", c do
    Boundary.with_scope(c.scope, fn ->
      exported = Boundary.with_query_action(:export, Page, fn -> Repo.all(Boundary.query(Page, Page)) end)
      assert Enum.map(exported, & &1.id) == [c.own.id]
      assert length(Repo.all(Boundary.query(Page, Page))) == 2
    end)
  end

  test "live previews recheck record policies after ownership changes", c do
    alias Brando.Authorization.Preview
    key = "POLICY-PREVIEW-#{Ecto.UUID.generate()}"
    own = Repo.get!(Page, c.own.id)
    assert :ok = Boundary.with_scope(c.scope, fn -> Preview.register(key, Ecto.Changeset.change(own)) end)
    on_exit(fn -> Preview.cleanup(key) end)
    assert :ok = Preview.authorize(key, c.scope.user_id)
    Repo.update_all(from(p in Page, where: p.id == ^own.id), set: [creator_id: c.foreign.creator_id])
    assert {:error, :forbidden} = Preview.authorize(key, c.scope.user_id)
  end

  test "a policy without a query implementation fails closed", c do
    assert [] == Repo.all(Engine.scope(c.scope, :read, UnscopedPage))
  end

  test "mutation notifications respect record read policies", c do
    alias Brando.Authorization.Realtime
    payload = %{authorization: %{prefix: c.scope.prefix, schema: Page, entry_id: c.own.id}}
    assert Realtime.notification_allowed?(c.scope, payload)
    refute Realtime.notification_allowed?(c.scope, put_in(payload, [:authorization, :entry_id], c.foreign.id))
  end
end

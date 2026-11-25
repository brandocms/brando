defmodule Brando.Test.CommittedTest do
  use ExUnit.Case, async: false

  alias Brando.Revisions.Revision
  alias Brando.Test.Committed
  alias BrandoIntegration.Repo
  alias Ecto.Adapters.SQL.Sandbox

  setup_all do
    Committed.template()
  end

  test "committed rows belong to the test database, including from another connection", %{template: template} do
    type = "CommittedTest#{Ecto.UUID.generate()}"
    revision = %Revision{entry_id: 0, entry_type: type, encoded_entry: "", metadata: %{}, revision: 0}

    on_exit(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        try do
          assert Repo.query!("SELECT revision FROM revisions WHERE entry_type = $1 ORDER BY revision", [type]).rows ==
                   [[0], [1]]
        after
          Repo.query!("DELETE FROM revisions WHERE entry_type = $1", [type])
        end
      end)
    end)

    Sandbox.unboxed_run(Repo, fn -> Repo.insert!(revision) end)
    shared_key = Brando.Cache.Query.hash_query({:list, "revisions", []})
    :ok = Committed.start(template)
    private_key = Brando.Cache.Query.hash_query({:list, "revisions", []})
    refute private_key == shared_key
    test = self()
    spawn(fn -> send(test, {:worker_key, Brando.Cache.Query.hash_query({:list, "revisions", []})}) end)
    assert_receive {:worker_key, ^private_key}

    # The shared pool still requires an owner even while the private one is live.
    assert_raise DBConnection.OwnershipError, fn -> Repo.query!("SELECT 1") end
    Task.async(fn -> Sandbox.unboxed_run(Repo, fn -> Repo.insert!(%{revision | revision: 1}) end) end) |> Task.await()

    Brando.Repo.insert!(%{revision | revision: 2})
    assert Task.async(fn -> Brando.Repo.get_by!(Revision, entry_type: type).revision end) |> Task.await() == 2
  end
end

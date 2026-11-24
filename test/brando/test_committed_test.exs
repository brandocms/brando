defmodule Brando.Test.CommittedTest do
  # The helper's cleanup, on committed rows: not async, as the repo's mode is
  # the whole run's.
  use ExUnit.Case, async: false

  alias Brando.Revisions.Revision
  alias BrandoIntegration.Repo
  alias Ecto.Adapters.SQL.Sandbox

  # A revision has no id, and its `inserted_at` is stored to the second, below
  # a mark taken in the same second
  test "deletes what the test committed, rows stored to the second included" do
    before = Sandbox.unboxed_run(Repo, &counts/0)
    # Registered first, so it runs after the helper's cleanup
    on_exit(fn -> assert Sandbox.unboxed_run(Repo, &counts/0) == before end)

    Brando.Test.Committed.start()

    Repo.insert!(%Revision{
      entry_id: 0,
      entry_type: "Brando.Test.Committed",
      encoded_entry: "",
      metadata: %{},
      revision: 0
    })
  end

  defp counts do
    %{rows: tables} =
      Repo.query!(
        "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE'"
      )

    for [table] <- tables, into: %{} do
      %{rows: [[count]]} = Repo.query!(~s|SELECT count(*) FROM public."#{table}"|)
      {table, count}
    end
  end
end

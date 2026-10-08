defmodule Brando.Migrations.Brando216AddProposalsToActivityEventsTest do
  # Runs the upgrade template inside the sandbox transaction against tables
  # rolled back to before it; Postgres DDL is transactional, so everything
  # is undone afterwards.
  use ExUnit.Case
  use Brando.ConnCase

  import Brando.MigrationTemplates

  @template "brando_216_add_proposals_to_activity_events.exs"
  @tenant "tenant_acme_staging"
  @columns ~w(proposal_id approver_id)

  defp definitions(schema), do: schema |> column_definitions("activity_events") |> Enum.filter(&(elem(&1, 0) in @columns))
  defp proposal_index(schema), do: schema |> indexes("activity_events") |> Enum.filter(&(&1 =~ "proposal_id"))

  defp insert(schema, source, action, user_id) do
    [[id]] =
      rows(
        """
        INSERT INTO "#{schema}".activity_events (action, source, user_id, schema, entry_id, inserted_at)
        VALUES ($1, $2, $3, 'Elixir.Brando.Pages.Page', 1, now()) RETURNING id
        """,
        [action, source, user_id]
      )

    id
  end

  defp approver(schema, id),
    do: rows(~s{SELECT approver_id, proposal_id FROM "#{schema}".activity_events WHERE id = $1}, [id])

  test "adds the proposal and the approver in public and every environment, and removes them" do
    expected = {definitions("public"), proposal_index("public")}
    query!("DROP INDEX activity_events_proposal_id_index")
    query!("ALTER TABLE activity_events DROP COLUMN proposal_id, DROP COLUMN approver_id")
    create_environment(@tenant, ["activity_events"])

    version = up(@template)

    for schema <- ["public", @tenant] do
      assert {definitions(schema), proposal_index(schema)} == expected
      assert {"approver_id", "public", "users"} in references(schema, "activity_events")
    end

    down(@template, version)

    for schema <- ["public", @tenant] do
      assert definitions(schema) == []
      assert proposal_index(schema) == []
    end
  end

  test "an agent's earlier changes were approved by their user; the rest are left as they were" do
    user = Brando.Factory.insert(:random_user)
    query!("DROP INDEX activity_events_proposal_id_index")
    query!("ALTER TABLE activity_events DROP COLUMN proposal_id, DROP COLUMN approver_id")
    create_environment(@tenant, ["activity_events"])

    inserted =
      for schema <- ["public", @tenant] do
        {schema,
         %{
           by_hand: insert(schema, "admin", "updated", user.id),
           assistant: insert(schema, "assistant", "updated", user.id),
           mcp: insert(schema, "mcp", "published", user.id),
           tool_call: insert(schema, "mcp", "tool_called", user.id),
           scheduled: insert(schema, "scheduler", "published", user.id),
           system: insert(schema, "system", "deleted", nil)
         }}
      end

    up(@template)

    for {schema, ids} <- inserted do
      assert approver(schema, ids.assistant) == [[user.id, nil]]
      assert approver(schema, ids.mcp) == [[user.id, nil]]

      for kind <- [:by_hand, :tool_call, :scheduled, :system] do
        assert approver(schema, ids[kind]) == [[nil, nil]]
      end
    end
  end
end

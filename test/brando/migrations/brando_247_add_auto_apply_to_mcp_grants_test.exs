defmodule Brando.Migrations.Brando247AddAutoApplyToMCPGrantsTest do
  # Runs the upgrade template inside the sandbox transaction against tables
  # rolled back to before it; Postgres DDL is transactional, so everything
  # is undone afterwards.
  use Brando.ConnCase

  import Brando.MigrationTemplates, only: [down: 2, query!: 1, rows: 2, up: 1]

  @file_name "brando_247_add_auto_apply_to_mcp_grants.exs"

  defp columns(table, names),
    do:
      rows(
        "SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = $1 AND column_name = ANY($2)",
        [table, names]
      )
      |> List.flatten()
      |> Enum.sort()

  @grant_columns ~w(auto_apply auto_apply_set_at auto_apply_set_by_id)
  @proposal_columns Enum.sort(~w(auto_apply_reason auto_applied_grant_id))

  # An existing connection applies nothing without review
  test "adds what a connection may apply without review, none for every connection, and rolls back" do
    user = Brando.Factory.insert(:random_user)

    query!(
      "INSERT INTO public.mcp_grants (user_id, resource, client_id, client_name, redirect_uri, scope, inserted_at, updated_at) " <>
        "VALUES (#{user.id}, 'https://example.com/mcp', 'https://client.example/meta', 'Client', 'https://client.example/cb', 'content', now(), now())"
    )

    query!(
      "ALTER TABLE public.mcp_grants DROP COLUMN auto_apply, DROP COLUMN auto_apply_set_by_id, DROP COLUMN auto_apply_set_at"
    )

    query!("ALTER TABLE public.content_proposals DROP COLUMN auto_applied_grant_id, DROP COLUMN auto_apply_reason")

    version = up(@file_name)

    assert columns("mcp_grants", @grant_columns) == @grant_columns
    assert columns("content_proposals", @proposal_columns) == @proposal_columns

    assert rows("SELECT client_name, auto_apply, auto_apply_set_by_id, auto_apply_set_at FROM public.mcp_grants", []) ==
             [["Client", "none", nil, nil]]

    down(@file_name, version)

    assert columns("mcp_grants", @grant_columns) == []
    assert columns("content_proposals", @proposal_columns) == []
  end
end

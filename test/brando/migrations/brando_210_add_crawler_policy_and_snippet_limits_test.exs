defmodule Brando.Migrations.Brando210AddCrawlerPolicyAndSnippetLimitsTest do
  # Runs the upgrade template inside the sandbox transaction against tables
  # rolled back to before it; Postgres DDL is transactional, so everything
  # is undone afterwards.
  use ExUnit.Case
  use Brando.ConnCase

  import Brando.MigrationTemplates

  @template "brando_210_add_crawler_policy_and_snippet_limits.exs"
  @tenant "tenant_acme_staging"
  @columns %{"sites_seos" => ~w(crawler_policy), "pages" => ~w(meta_nosnippet meta_max_snippet)}

  defp definitions(schema, table),
    do: schema |> column_definitions(table) |> Enum.filter(&(elem(&1, 0) in @columns[table]))

  test "adds its columns in public and every environment, and removes them" do
    expected = Map.new(@columns, fn {table, _} -> {table, definitions("public", table)} end)
    query!("ALTER TABLE sites_seos DROP COLUMN crawler_policy")
    query!("ALTER TABLE pages DROP COLUMN meta_nosnippet, DROP COLUMN meta_max_snippet")
    create_environment(@tenant, Map.keys(@columns))

    version = up(@template)

    for schema <- ["public", @tenant], table <- Map.keys(@columns) do
      assert definitions(schema, table) == expected[table]
    end

    down(@template, version)

    for schema <- ["public", @tenant], table <- Map.keys(@columns) do
      assert definitions(schema, table) == []
    end
  end
end

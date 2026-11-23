defmodule Brando.Migrations.Brando243AddSitesUsageDaysTest do
  use Brando.ConnCase

  import Brando.MigrationTemplates, only: [columns: 2, down: 2, indexes: 2, query!: 1, table?: 2, up: 1]

  @file_name "brando_243_add_sites_usage_days.exs"

  test "creates the usage table with the columns the schema uses, in public, and rolls back" do
    expected = columns("public", "sites_usage_days")
    expected_indexes = indexes("public", "sites_usage_days")
    query!("DROP TABLE public.sites_usage_days")
    refute table?("public", "sites_usage_days")

    version = up(@file_name)

    assert columns("public", "sites_usage_days") == expected
    assert indexes("public", "sites_usage_days") == expected_indexes

    assert Enum.sort(expected) ==
             Brando.Sites.Usage.Day.__schema__(:fields) |> Enum.map(&to_string/1) |> Enum.sort()

    assert Brando.Tenant.SharedTables.member?("sites_usage_days")

    down(@file_name, version)
    refute table?("public", "sites_usage_days")
  end
end

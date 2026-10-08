defmodule Brando.Migrations.Brando215AddListingViewsTest do
  # Runs the upgrade template inside the sandbox transaction, with the tables
  # dropped first; Postgres DDL is transactional, so everything is undone.
  use ExUnit.Case
  use Brando.ConnCase

  import Brando.MigrationTemplates

  @template "brando_215_add_listing_views.exs"
  @tenant "tenant_acme_staging"
  @tables ~w(listing_views listing_view_defaults)

  test "creates the listing view tables in public and every environment, with the columns the schemas use" do
    expected = Map.new(@tables, &{&1, {column_definitions("public", &1), indexes("public", &1)}})
    query!("DROP TABLE public.listing_view_defaults, public.listing_views")
    create_environment(@tenant)

    version = up(@template)

    for schema <- ["public", @tenant] do
      for table <- @tables do
        assert {column_definitions(schema, table), indexes(schema, table)} == expected[table]
      end

      assert Enum.any?(indexes(schema, "listing_views"), &(&1 =~ "listing_views_creator_name_index"))
      assert Enum.any?(indexes(schema, "listing_view_defaults"), &(&1 =~ "listing_view_defaults_user_listing_index"))
      assert references(schema, "listing_views") == [{"creator_id", "public", "users"}]

      assert references(schema, "listing_view_defaults") == [
               {"user_id", "public", "users"},
               {"view_id", schema, "listing_views"}
             ]

      assert columns(schema, "listing_views") ==
               Brando.ListingViews.View.__schema__(:fields) |> Enum.map(&to_string/1) |> Enum.sort()

      assert columns(schema, "listing_view_defaults") ==
               Brando.ListingViews.Default.__schema__(:fields) |> Enum.map(&to_string/1) |> Enum.sort()
    end

    # Views belong to an environment's content: never pinned to public
    for table <- @tables, do: refute(Brando.Tenant.SharedTables.member?(table))

    down(@template, version)

    for schema <- ["public", @tenant], table <- @tables do
      refute table?(schema, table)
    end
  end
end

defmodule Brando.Migrations.Brando217AddNotificationRoutesTest do
  # Runs the upgrade template inside the sandbox transaction, with the tables
  # dropped first; Postgres DDL is transactional, so everything is undone.
  use ExUnit.Case
  use Brando.ConnCase

  import Brando.MigrationTemplates

  @template "brando_217_add_notification_routes.exs"
  @tenant "tenant_acme_staging"
  @tables ~w(notification_routes notification_deliveries)

  test "creates the notification tables in public and every environment, with the columns the schemas use" do
    expected = Map.new(@tables, &{&1, {column_definitions("public", &1), indexes("public", &1)}})
    query!("DROP TABLE public.notification_deliveries, public.notification_routes")
    create_environment(@tenant)

    version = up(@template)

    for schema <- ["public", @tenant] do
      for table <- @tables do
        assert {column_definitions(schema, table), indexes(schema, table)} == expected[table]
      end

      assert Enum.any?(indexes(schema, "notification_deliveries"), &(&1 =~ "notification_deliveries_once_per_event_index"))
      assert references(schema, "notification_routes") == [{"creator_id", "public", "users"}]

      assert Enum.sort(references(schema, "notification_deliveries")) ==
               Enum.sort([{"recipient_id", "public", "users"}, {"route_id", schema, "notification_routes"}])

      assert columns(schema, "notification_routes") ==
               (Brando.Notifications.Route.__schema__(:fields) -- [:url]) |> Enum.map(&to_string/1) |> Enum.sort()

      assert columns(schema, "notification_deliveries") ==
               Brando.Notifications.Delivery.__schema__(:fields) |> Enum.map(&to_string/1) |> Enum.sort()
    end

    down(@template, version)

    for schema <- ["public", @tenant], table <- @tables do
      refute table?(schema, table)
    end
  end
end

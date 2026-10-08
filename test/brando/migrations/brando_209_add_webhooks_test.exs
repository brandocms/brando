defmodule Brando.Migrations.Brando209AddWebhooksTest do
  # Runs the upgrade template inside the sandbox transaction, with the tables
  # dropped first; Postgres DDL is transactional, so everything is undone.
  use ExUnit.Case
  use Brando.ConnCase

  import Brando.MigrationTemplates

  @template "brando_209_add_webhooks.exs"
  @tenant "tenant_acme_staging"
  @tables ~w(webhooks webhook_deliveries)

  test "creates the webhook tables in public and every environment, with the columns the schemas use" do
    expected = Map.new(@tables, &{&1, {column_definitions("public", &1), indexes("public", &1)}})
    query!("DROP TABLE public.webhook_deliveries, public.webhooks")
    create_environment(@tenant)

    version = up(@template)

    for schema <- ["public", @tenant] do
      for table <- @tables do
        assert {column_definitions(schema, table), indexes(schema, table)} == expected[table]
      end

      assert Enum.any?(indexes(schema, "webhook_deliveries"), &(&1 =~ "webhook_deliveries_once_per_event_index"))
      assert references(schema, "webhooks") == [{"creator_id", "public", "users"}]
      assert references(schema, "webhook_deliveries") == [{"webhook_id", schema, "webhooks"}]

      assert columns(schema, "webhooks") ==
               Brando.Webhooks.Webhook.__schema__(:fields) |> Enum.map(&to_string/1) |> Enum.sort()

      assert columns(schema, "webhook_deliveries") ==
               Brando.Webhooks.Delivery.__schema__(:fields) |> Enum.map(&to_string/1) |> Enum.sort()
    end

    down(@template, version)

    for schema <- ["public", @tenant], table <- @tables do
      refute table?(schema, table)
    end
  end
end

defmodule Brando.Migrations.Brando209AddWebhooksTest do
  # Runs the upgrade template inside the sandbox transaction, with the tables
  # dropped first; Postgres DDL is transactional, so everything is undone.
  use ExUnit.Case
  use Brando.ConnCase

  alias BrandoIntegration.Repo

  @template Application.app_dir(:brando, "priv/templates/brando.upgrade/migrations/brando_209_add_webhooks.exs")

  defp run_template do
    [{module, _bytecode}] = Code.compile_file(@template)

    try do
      Ecto.Migrator.up(Repo, System.unique_integer([:positive]), module, log: false, migration_lock: false)
    after
      :code.purge(module)
      :code.delete(module)
    end
  end

  defp columns(table) do
    Repo.query!(
      "SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = $1",
      [table]
    ).rows
    |> List.flatten()
    |> Enum.sort()
  end

  test "creates the webhook tables with the columns the schemas use" do
    expected_webhooks = columns("webhooks")
    expected_deliveries = columns("webhook_deliveries")
    Repo.query!("DROP TABLE public.webhook_deliveries, public.webhooks")

    run_template()

    assert columns("webhooks") == expected_webhooks
    assert columns("webhook_deliveries") == expected_deliveries

    assert expected_webhooks ==
             Brando.Webhooks.Webhook.__schema__(:fields) |> Enum.map(&to_string/1) |> Enum.sort()

    assert expected_deliveries ==
             Brando.Webhooks.Delivery.__schema__(:fields) |> Enum.map(&to_string/1) |> Enum.sort()
  end
end

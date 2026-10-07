defmodule Brando.Migrations.Brando205AddPasskeysAndSessionDetailsTest do
  # Runs the upgrade template inside the sandbox transaction against a schema
  # rolled back to before it; Postgres DDL is transactional, so everything is
  # undone afterwards.
  use ExUnit.Case
  use Brando.ConnCase

  alias BrandoIntegration.Repo

  @template Application.app_dir(
              :brando,
              "priv/templates/brando.upgrade/migrations/brando_205_add_passkeys_and_session_details.exs"
            )
  @token_columns ~w(ip user_agent last_used_at confirmed_at)

  defp columns(table) do
    "SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = $1"
    |> Repo.query!([table])
    |> Map.fetch!(:rows)
    |> List.flatten()
  end

  defp run_template do
    [{module, _bytecode}] = Code.compile_file(@template)

    try do
      Ecto.Migrator.up(Repo, System.unique_integer([:positive]), module, log: false, migration_lock: false)
    after
      :code.purge(module)
      :code.delete(module)
    end
  end

  test "adds passkeys, and what a session needs for its list and for confirming again" do
    Repo.query!("DROP TABLE users_passkeys")
    Repo.query!("ALTER TABLE users_tokens " <> Enum.map_join(@token_columns, ", ", &"DROP COLUMN #{&1}"))

    run_template()
    assert "credential_id" in columns("users_passkeys")
    assert Enum.all?(@token_columns, &(&1 in columns("users_tokens")))

    run_template()
    assert Brando.Tenant.SharedTables.member?("users_passkeys")
  end
end

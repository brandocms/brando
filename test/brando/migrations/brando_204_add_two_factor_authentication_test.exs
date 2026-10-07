defmodule Brando.Migrations.Brando204AddTwoFactorAuthenticationTest do
  # Runs the upgrade template inside the sandbox transaction against a schema
  # rolled back to before it; Postgres DDL is transactional, so everything is
  # undone afterwards.
  use ExUnit.Case
  use Brando.ConnCase

  alias BrandoIntegration.Repo

  @template Application.app_dir(
              :brando,
              "priv/templates/brando.upgrade/migrations/brando_204_add_two_factor_authentication.exs"
            )
  @tables ~w(users_security users_recovery_codes users_security_events users_security_policy)

  defp tables do
    "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' AND table_name = ANY($1)"
    |> Repo.query!([@tables])
    |> Map.fetch!(:rows)
    |> List.flatten()
    |> Enum.sort()
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

  test "creates the two-factor tables in public, and runs again without harm" do
    Repo.query!("DROP TABLE #{Enum.join(@tables, ", ")}")
    assert tables() == []

    run_template()
    assert tables() == Enum.sort(@tables)

    run_template()
    assert tables() == Enum.sort(@tables)
    assert Enum.all?(@tables, &Brando.Tenant.SharedTables.member?/1)
  end
end

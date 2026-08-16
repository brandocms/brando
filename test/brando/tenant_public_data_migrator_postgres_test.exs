defmodule Brando.TenantPublicDataMigratorPostgresTest do
  use ExUnit.Case, async: false

  alias Brando.IntegrationRepo
  alias Brando.Tenant.PublicDataMigrator.Postgres

  defmodule Repo do
    use Ecto.Repo,
      otp_app: :brando,
      adapter: Ecto.Adapters.Postgres
  end

  setup_all do
    IntegrationRepo.start(Repo)
  end

  setup do
    previous_repo = Application.fetch_env(:brando, :repo_module)
    Application.put_env(:brando, :repo_module, Repo)

    unique = System.unique_integer([:positive])
    table = "migration_records_#{unique}"
    target = "tenant_publicmigration#{unique}_production"

    Ecto.Adapters.SQL.query!(Repo, ~s|CREATE TABLE public."#{table}" (id serial PRIMARY KEY, name text NOT NULL)|, [])
    Ecto.Adapters.SQL.query!(Repo, ~s|INSERT INTO public."#{table}" (name) VALUES ('legacy-one'), ('legacy-two')|, [])
    Ecto.Adapters.SQL.query!(Repo, ~s|CREATE SCHEMA "#{target}"|, [])

    Ecto.Adapters.SQL.query!(
      Repo,
      ~s|CREATE TABLE "#{target}"."#{table}" (id serial PRIMARY KEY, name text NOT NULL)|,
      []
    )

    on_exit(fn ->
      Ecto.Adapters.SQL.query!(Repo, ~s|DROP SCHEMA IF EXISTS "#{target}" CASCADE|, [])
      Ecto.Adapters.SQL.query!(Repo, ~s|DROP TABLE IF EXISTS public."#{table}" CASCADE|, [])
      IntegrationRepo.restore_env(:repo_module, previous_repo)
    end)

    %{table: table, target: target}
  end

  test "copies data only for tables present in the migrated tenant schema", context do
    assert :ok = Postgres.migrate("public", context.target)

    assert %{rows: [["legacy-one"], ["legacy-two"]]} =
             Ecto.Adapters.SQL.query!(
               Repo,
               ~s|SELECT name FROM "#{context.target}"."#{context.table}" ORDER BY id|,
               []
             )
  end
end

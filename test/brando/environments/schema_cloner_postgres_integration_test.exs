defmodule Brando.Environments.SchemaCloner.PostgresIntegrationTest do
  use ExUnit.Case, async: false

  alias Brando.Environments.SchemaCloner.Postgres

  defmodule Repo do
    use Ecto.Repo,
      otp_app: :brando,
      adapter: Ecto.Adapters.Postgres
  end

  setup_all do
    integration_config = BrandoIntegration.Repo.config()

    repo_options =
      integration_config
      |> Keyword.take([:database, :hostname, :password, :port, :socket_options, :ssl, :username])
      |> Keyword.merge(pool: DBConnection.ConnectionPool, pool_size: 2)

    {:ok, repo} = Repo.start_link(repo_options)

    on_exit(fn ->
      try do
        GenServer.stop(repo)
      catch
        :exit, _ -> :ok
      end
    end)

    :ok
  end

  setup do
    unique = System.unique_integer([:positive])
    source = "tenant_cloner#{unique}_source"
    target = "tenant_cloner#{unique}_target"

    Ecto.Adapters.SQL.query!(Repo, ~s|CREATE SCHEMA "#{source}"|, [])

    Ecto.Adapters.SQL.query!(
      Repo,
      ~s|CREATE TABLE "#{source}".records (id serial PRIMARY KEY, name text NOT NULL)|,
      []
    )

    Ecto.Adapters.SQL.query!(
      Repo,
      ~s|INSERT INTO "#{source}".records (name) VALUES ('one'), ('two')|,
      []
    )

    on_exit(fn ->
      Ecto.Adapters.SQL.query!(Repo, ~s|DROP SCHEMA IF EXISTS "#{target}" CASCADE|, [])
      Ecto.Adapters.SQL.query!(Repo, ~s|DROP SCHEMA IF EXISTS "#{source}" CASCADE|, [])
    end)

    %{source: source, target: target}
  end

  test "keeps pg_dump warnings out of the dump", context do
    # Circular foreign keys make pg_dump warn on stderr. Merging that stream
    # into stdout spliced the prose into the SQL, and psql then failed with
    # `syntax error at or near "pg_dump"`.
    q = fn sql -> Ecto.Adapters.SQL.query!(Repo, sql, []) end
    src = context.source

    q.(~s|CREATE TABLE "#{src}".a (id integer PRIMARY KEY, b_id integer)|)
    q.(~s|CREATE TABLE "#{src}".b (id integer PRIMARY KEY, a_id integer)|)
    q.(~s|ALTER TABLE "#{src}".a ADD CONSTRAINT a_b FOREIGN KEY (b_id) REFERENCES "#{src}".b(id)|)
    q.(~s|ALTER TABLE "#{src}".b ADD CONSTRAINT b_a FOREIGN KEY (a_id) REFERENCES "#{src}".a(id)|)

    assert {:ok, dump} = Postgres.dump_schema(src, ["--data-only"])

    refute dump =~ "pg_dump:"
    refute dump =~ "circular foreign-key"
    assert dump =~ "COPY"
  end

  test "pg_dump and psql clone schema structure, data, and sequence defaults", context do
    assert :ok = Postgres.clone_schema(context.source, context.target)

    assert %{rows: [[1, "one"], [2, "two"]]} =
             Ecto.Adapters.SQL.query!(
               Repo,
               ~s|SELECT id, name FROM "#{context.target}".records ORDER BY id|,
               []
             )

    assert %{rows: [[3]]} =
             Ecto.Adapters.SQL.query!(
               Repo,
               ~s|INSERT INTO "#{context.target}".records (name) VALUES ('three') RETURNING id|,
               []
             )
  end
end

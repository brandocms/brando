defmodule Brando.Environments.StructureCloner.PostgresIntegrationTest do
  use ExUnit.Case, async: false

  alias Brando.Environments.StructureCloner.Postgres

  defmodule Repo do
    use Ecto.Repo,
      otp_app: :brando,
      adapter: Ecto.Adapters.Postgres
  end

  setup_all do
    repo_options =
      BrandoIntegration.Repo.config()
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
    # tenant_tables/1 reads through the application repo, so it needs an owner.
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(BrandoIntegration.Repo, shared: true)

    unique = System.unique_integer([:positive])
    source = "tenant_struct#{unique}_source"
    target = "tenant_struct#{unique}_target"

    # The source and target schemas must be committed, because pg_dump and psql
    # connect outside the sandbox and cannot see an open transaction.
    query!(~s|CREATE SCHEMA "#{source}"|)
    query!(~s|CREATE SCHEMA "#{target}"|)

    query!("""
    CREATE TABLE "#{source}".records (
      id serial PRIMARY KEY,
      name text NOT NULL,
      creator_id bigint REFERENCES "public".users(id)
    )
    """)

    query!(~s|CREATE TABLE "#{source}".oban_peers (name text PRIMARY KEY)|)
    query!(~s|INSERT INTO "#{source}".records (name) VALUES ('one'), ('two')|)

    on_exit(fn ->
      query!(~s|DROP SCHEMA IF EXISTS "#{target}" CASCADE|)
      query!(~s|DROP SCHEMA IF EXISTS "#{source}" CASCADE|)
      Ecto.Adapters.SQL.Sandbox.stop_owner(pid)
    end)

    %{source: source, target: target}
  end

  test "clones structure without data and gives the target its own sequence", context do
    assert :ok = Postgres.clone_structure(context.source, context.target)

    assert %{rows: [[0]]} = query!(~s|SELECT count(*) FROM "#{context.target}".records|)

    assert %{rows: [[1]]} =
             query!(~s|INSERT INTO "#{context.target}".records (name) VALUES ('a') RETURNING id|)

    assert %{rows: [[3]]} =
             query!(~s|INSERT INTO "#{context.source}".records (name) VALUES ('c') RETURNING id|)
  end

  test "keeps foreign keys pointing at the shared public table", context do
    assert :ok = Postgres.clone_structure(context.source, context.target)

    assert %{rows: [["public", "users"]]} =
             query!("""
             SELECT n.nspname, r.relname
             FROM pg_constraint c
             JOIN pg_class r ON r.oid = c.confrelid
             JOIN pg_namespace n ON n.oid = r.relnamespace
             WHERE c.contype = 'f' AND c.connamespace = '#{context.target}'::regnamespace
             """)
  end

  test "does not clone shared tables into the target", context do
    assert :ok = Postgres.clone_structure(context.source, context.target)

    assert %{rows: [["records"]]} =
             query!(~s|SELECT tablename FROM pg_tables WHERE schemaname = '#{context.target}' ORDER BY 1|)
  end

  test "clones a table whose column uses a type owned by the source schema", context do
    query!(~s|CREATE TYPE "#{context.source}".probe_state AS ENUM ('draft', 'live')|)

    query!("""
    CREATE TABLE "#{context.source}".typed (
      id serial PRIMARY KEY,
      state "#{context.source}".probe_state NOT NULL DEFAULT 'draft'
    )
    """)

    assert :ok = Postgres.clone_structure(context.source, context.target)

    # The type is used from the source schema, not recreated in the target.
    assert %{rows: [[0]]} =
             query!(
               "SELECT count(*) FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace WHERE n.nspname = '#{context.target}' AND t.typname = 'probe_state'"
             )

    assert %{rows: [["live"]]} =
             query!(~s|INSERT INTO "#{context.target}".typed (state) VALUES ('live') RETURNING state|)
  end

  test "clones table names that are not lowercase snake_case", context do
    # An unquoted pg_dump --table pattern is case-folded and treats * ? [ as
    # wildcards, so each of these would silently miss without quoting.
    for name <- ["LegacyTable", "has-hyphen", "dot.ted", "Ölmengde", "star*name"] do
      query!(~s|CREATE TABLE "#{context.source}"."#{name}" (id serial PRIMARY KEY)|)
    end

    assert :ok = Postgres.clone_structure(context.source, context.target)

    assert {:ok, cloned} = Postgres.tenant_tables(context.target)

    for name <- ["LegacyTable", "has-hyphen", "dot.ted", "Ölmengde", "star*name"] do
      assert name in cloned, "expected #{name} to be cloned"
    end
  end

  test "refuses a table name containing a double quote, unless declared shared", context do
    query!(~s|CREATE TABLE "#{context.source}"."we""ird" (id serial PRIMARY KEY)|)

    assert {:error, {:unsafe_source_table_name, [~s|we"ird|]}} =
             Postgres.clone_structure(context.source, context.target)

    previous = Application.get_env(:brando, :shared_tables)
    Application.put_env(:brando, :shared_tables, [~s|we"ird|])
    on_exit(fn -> Application.put_env(:brando, :shared_tables, previous) end)

    assert :ok = Postgres.clone_structure(context.source, context.target)
  end

  test "fails when the source holds no tenant tables", context do
    query!(~s|DROP TABLE "#{context.source}".records|)

    assert {:error, {:no_tenant_tables, source}} =
             Postgres.clone_structure(context.source, context.target)

    assert source == context.source
  end

  defp query!(sql), do: Ecto.Adapters.SQL.query!(Repo, sql, [])
end

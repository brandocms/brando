defmodule Brando.Tenant.PublicDataMigrator.MoveIntegrationTest do
  use ExUnit.Case, async: false

  alias Brando.Tenant.PublicDataMigrator.Move

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

    # Move runs its own statements through the application repo and shells out to
    # pg_dump/psql, which connect separately and cannot see an open sandbox
    # transaction. Autocommit for this file keeps the two views consistent.
    Ecto.Adapters.SQL.Sandbox.mode(BrandoIntegration.Repo, :auto)

    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.mode(BrandoIntegration.Repo, :manual)

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
    source = "tenant_move#{unique}_source"
    target = "tenant_move#{unique}_target"

    query!(~s|CREATE SCHEMA "#{source}"|)
    query!(~s|CREATE SCHEMA "#{target}"|)

    # `source` stands in for public: populated content plus a shared table that
    # must not move. `target` holds the empty clone provisioning leaves behind.
    query!("""
    CREATE TABLE "#{source}".records (
      id serial PRIMARY KEY,
      name text NOT NULL,
      creator_id bigint REFERENCES "public".users(id)
    )
    """)

    query!(~s|CREATE TABLE "#{source}".oban_peers (name text PRIMARY KEY)|)
    query!(~s|INSERT INTO "#{source}".records (name) VALUES ('one'), ('two'), ('three')|)
    query!(~s|INSERT INTO "#{source}".oban_peers (name) VALUES ('peer')|)

    query!("""
    CREATE TABLE "#{target}".records (
      id serial PRIMARY KEY,
      name text NOT NULL,
      creator_id bigint REFERENCES "public".users(id)
    )
    """)

    on_exit(fn ->
      query!(~s|DROP SCHEMA IF EXISTS "#{target}" CASCADE|)
      query!(~s|DROP SCHEMA IF EXISTS "#{source}" CASCADE|)
    end)

    %{source: source, target: target}
  end

  test "relocates rows into the target and leaves an empty template behind", context do
    assert :ok = Move.migrate(context.source, context.target)

    assert %{rows: [[3]]} = query!(~s|SELECT count(*) FROM "#{context.target}".records|)
    assert %{rows: [[0]]} = query!(~s|SELECT count(*) FROM "#{context.source}".records|)

    assert %{rows: [["one"], ["three"], ["two"]]} =
             query!(~s|SELECT name FROM "#{context.target}".records ORDER BY name|)
  end

  test "carries sequence position across so the next insert does not collide", context do
    assert :ok = Move.migrate(context.source, context.target)

    assert %{rows: [[4]]} =
             query!(~s|INSERT INTO "#{context.target}".records (name) VALUES ('four') RETURNING id|)

    # The rebuilt template starts from a fresh sequence.
    assert %{rows: [[1]]} =
             query!(~s|INSERT INTO "#{context.source}".records (name) VALUES ('x') RETURNING id|)
  end

  test "preserves the foreign key to the shared public table", context do
    assert :ok = Move.migrate(context.source, context.target)

    for schema <- [context.target, context.source] do
      assert %{rows: [["public", "users"]]} =
               query!("""
               SELECT n.nspname, r.relname
               FROM pg_constraint c
               JOIN pg_class r ON r.oid = c.confrelid
               JOIN pg_namespace n ON n.oid = r.relnamespace
               WHERE c.contype = 'f' AND c.connamespace = '#{schema}'::regnamespace
               """)
    end
  end

  test "never moves a shared table", context do
    assert :ok = Move.migrate(context.source, context.target)

    assert %{rows: [[1]]} = query!(~s|SELECT count(*) FROM "#{context.source}".oban_peers|)

    assert %{rows: [[false]]} =
             query!(
               "SELECT EXISTS(SELECT 1 FROM pg_tables WHERE schemaname = '#{context.target}' AND tablename = 'oban_peers')"
             )
  end

  test "leaves no template schema behind", context do
    assert :ok = Move.migrate(context.source, context.target)

    assert %{rows: [[0]]} =
             query!("SELECT count(*) FROM pg_namespace WHERE nspname LIKE 'tenant_template_%'")
  end

  defp query!(sql), do: Ecto.Adapters.SQL.query!(Repo, sql, [])
end

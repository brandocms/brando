defmodule Brando.Test.Database do
  @moduledoc """
  The test database a `mix test` run starts from (`test/test_helper.exs`).

  A run that was killed leaves the rows its tests had committed (a Site, a
  Superuser) and the schemas they made, which fail the next run's tests, and
  the databases of the upgrade tests (`Brando.UpgradeFromVillainCase`),
  named after the test database with `_villain_` and a hex suffix. So a run
  empties its database and seeds it, as a new one would be, and drops those
  databases, when no other session uses the database. Faster than dropping
  the database, which waits for a checkpoint.

  Several sessions share a machine's Postgres, and two runs in one checkout
  share its database. Each run holds an advisory lock on the database,
  shared, until it ends; the reset takes it exclusive first, and needs no
  other session connected, so it never empties a database that another run,
  a console or an older checkout without the lock is using. A run that finds
  another there starts on the database as it is.
  """

  alias BrandoIntegration.Repo

  # An advisory lock is the database's own: other databases' runs take theirs
  @lock 3_885_001

  # Dropping the schemas or the databases a killed run left can take long on
  # a busy server
  @ddl [timeout: :infinity]

  @doc """
  Starts the test repo, on its database emptied and seeded when no other
  session uses it. The lock's connection is linked to the caller, and its
  lock goes with it.
  """
  def start_repo! do
    {:ok, conn} = Postgrex.start_link(connection_options())
    exclusive? = query!(conn, "SELECT pg_try_advisory_lock($1)", [@lock]) == [[true]]

    # Before the repo connects: its connections would count as another session
    alone? = exclusive? and others(conn) == 0

    {:ok, _} = Repo.start_link()

    if alone? do
      empty!()
      Code.eval_file("priv/repo/seeds.exs")
      drop_upgrade_databases!(conn)
    end

    # Waits while another run resets
    query!(conn, "SELECT pg_advisory_lock_shared($1)", [@lock], @ddl)
    if exclusive?, do: query!(conn, "SELECT pg_advisory_unlock($1)", [@lock])
    :ok
  end

  defp connection_options do
    Repo.config()
    |> Keyword.take([:hostname, :port, :socket_dir, :username, :password, :database, :ssl, :parameters])
    |> Keyword.put(:pool_size, 1)
  end

  defp others(conn) do
    [[count]] =
      query!(
        conn,
        "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND pid <> pg_backend_pid() " <>
          "AND backend_type = 'client backend'",
        []
      )

    count
  end

  defp empty! do
    Repo.query!(
      """
      DO $$
      DECLARE name text;
      BEGIN
        FOR name IN
          SELECT nspname FROM pg_namespace
          WHERE nspname NOT IN ('public', 'information_schema') AND nspname NOT LIKE 'pg\\_%'
        LOOP
          EXECUTE format('DROP SCHEMA %I CASCADE', name);
        END LOOP;

        EXECUTE (
          SELECT 'TRUNCATE ' || string_agg(format('%I', tablename), ', ') || ' RESTART IDENTITY CASCADE'
          FROM pg_tables
          WHERE schemaname = 'public' AND tablename <> 'schema_migrations'
        );
      END $$
      """,
      [],
      @ddl
    )
  end

  # Only this database's: no other run uses them while none uses it
  defp drop_upgrade_databases!(conn) do
    own = ~r/^#{Regex.escape(Repo.config()[:database])}_villain_[0-9a-f]{8}$/

    for [name] <- query!(conn, "SELECT datname FROM pg_database", []), name =~ own do
      query!(conn, ~s(DROP DATABASE IF EXISTS "#{name}"), [], @ddl)
    end
  end

  defp query!(conn, sql, params, opts \\ []), do: Postgrex.query!(conn, sql, params, opts).rows
end

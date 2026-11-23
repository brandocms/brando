defmodule Brando.Test.Database do
  @moduledoc """
  The test database a `mix test` run starts from (`test/test_helper.exs`).

  A run that was killed leaves the rows its tests had committed (a Site, a
  Superuser) and the schemas they made, which fail the next run's tests, and
  the databases of the upgrade tests (`Brando.UpgradeFromVillainCase`),
  named by `upgrade_database/2`. So a run empties its database and seeds it,
  as a new one would be, and drops those databases, when no other session
  uses the database. Faster than dropping the database, which waits for a
  checkpoint.

  Several sessions share a machine's Postgres, and two runs in one checkout
  share its database. Each run holds an advisory lock on the database,
  shared, until it ends; the reset takes it exclusive first, and needs no
  other session connected, so it never empties a database that another run,
  a console or an older checkout without the lock is using. One of those
  that connects between the check and the reset is not seen. A run that finds
  another there starts on the database as it is, and says so.
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
    connected = if exclusive?, do: others(conn), else: 0

    {:ok, _} = Repo.start_link()

    cond do
      not exclusive? ->
        IO.puts(:stderr, "Test database #{database()} not reset: another test run is using it")

      connected > 0 ->
        IO.puts(:stderr, "Test database #{database()} not reset: #{connected} other session(s) connected")

      # Without tables, not migrated: test_helper.exs says how to rebuild it
      tables?(conn) ->
        empty!()
        Code.eval_file("priv/repo/seeds.exs")
        drop_upgrade_databases!(conn)

      true ->
        :ok
    end

    # Waits while another run resets
    query!(conn, "SELECT pg_advisory_lock_shared($1)", [@lock], @ddl)
    if exclusive?, do: query!(conn, "SELECT pg_advisory_unlock($1)", [@lock])
    :ok
  end

  @doc """
  A new name for an upgrade test's database, made from `database` and a
  random suffix. The `-` marks it: a worktree's test database has only
  `[a-z0-9_]` in its name. A `database` too long to leave room within
  Postgres's 63 bytes keeps its start and a digest of the whole, so a
  partition's name never shares the prefix of another's.
  """
  def upgrade_database(database) do
    upgrade_prefix(database) <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
  end

  @doc "Whether `name` is one `upgrade_database/1` gives for `database`."
  def upgrade_database?(name, database), do: name =~ ~r/^#{Regex.escape(upgrade_prefix(database))}[0-9a-f]{8}$/

  defp upgrade_prefix(database) when byte_size(database) <= 46, do: database <> "-villain-"

  defp upgrade_prefix(database) do
    digest = :sha256 |> :crypto.hash(database) |> Base.encode16(case: :lower) |> binary_part(0, 8)
    clip(database, 37) <> "-" <> digest <> "-villain-"
  end

  defp clip(string, bytes) when byte_size(string) <= bytes, do: string
  defp clip(string, bytes), do: clip(String.slice(string, 0..-2//1), bytes)

  defp database, do: Repo.config()[:database]

  defp connection_options do
    Repo.config()
    |> Keyword.take([:hostname, :port, :socket_dir, :username, :password, :database, :ssl, :parameters])
    |> Keyword.put(:pool_size, 1)
  end

  defp others(conn) do
    [[count]] =
      query!(
        conn,
        # Postgres hides most columns of another role's sessions from a role
        # without pg_read_all_stats (backend_type reads NULL), so only the
        # background workers it shows (autovacuum, parallel workers) are left out
        """
        SELECT count(*) FROM pg_stat_activity
        WHERE datname = current_database() AND pid <> pg_backend_pid()
          AND coalesce(backend_type, 'client backend') = 'client backend'
        """,
        []
      )

    count
  end

  defp tables?(conn) do
    query!(conn, "SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename <> 'schema_migrations' LIMIT 1", []) !=
      []
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

  # Only this database's: no run uses them while none uses this one, but a
  # console may
  defp drop_upgrade_databases!(conn) do
    for [name] <- query!(conn, "SELECT datname FROM pg_database", []), upgrade_database?(name, database()) do
      case Postgrex.query(conn, ~s(DROP DATABASE IF EXISTS "#{name}"), [], @ddl) do
        {:ok, _} -> :ok
        {:error, %Postgrex.Error{postgres: %{code: :object_in_use}}} -> IO.puts(:stderr, "Not dropped, in use: #{name}")
      end
    end
  end

  defp query!(conn, sql, params, opts \\ []), do: Postgrex.query!(conn, sql, params, opts).rows
end

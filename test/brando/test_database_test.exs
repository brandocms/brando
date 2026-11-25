defmodule Brando.Test.DatabaseTest do
  use ExUnit.Case, async: true

  alias Brando.Test.Database
  alias BrandoIntegration.Repo

  test "setup and startup refuse a populated, unmarked database and keep its contents" do
    config = isolated_database()
    :ok = Ecto.Adapters.Postgres.storage_up(config)
    on_exit(fn -> drop(config) end)

    with_connection(config, fn conn ->
      Postgrex.query!(conn, "CREATE TABLE sentinel AS SELECT 25 AS value", [])
      Postgrex.query!(conn, "CREATE SCHEMA retained", [])
      assert_raise RuntimeError, ~r/not provisioned/, fn -> Database.require_fixture!(conn, :unit) end
    end)

    assert_raise RuntimeError, ~r/not provisioned/, fn -> Database.provision!(config) end

    with_connection(config, fn conn ->
      assert %{rows: [[25, true]]} =
               Postgrex.query!(conn, "SELECT value, to_regnamespace('retained') IS NOT NULL FROM sentinel", [])
    end)
  end

  test "a newly provisioned database is recognized on later connections only for its fixture kind" do
    config = isolated_database()
    first = Task.async(fn -> Database.provision!(config) end)
    second = Task.async(fn -> Database.provision!(config) end)
    assert :ok = Task.await(first, :timer.seconds(30))
    on_exit(fn -> drop(config) end)
    assert :ok = Task.await(second, :timer.seconds(30))
    assert :ok = Database.provision!(config)

    with_connection(config, fn conn ->
      assert :ok = Database.require_fixture!(conn, :unit)
      assert_raise RuntimeError, ~r/not provisioned/, fn -> Database.require_fixture!(conn, :upgrade) end
    end)

    # A database created FROM TEMPLATE can have exactly the same tables.
    # Restoring its comment as well still cannot authorize resetting the copy.
    copy = isolated_database()
    :ok = Ecto.Adapters.Postgres.storage_up(Keyword.put(copy, :template, config[:database]))
    on_exit(fn -> drop(copy) end)

    with_connection(copy, fn conn ->
      %{rows: [[restore_comment]]} =
        Postgrex.query!(
          conn,
          """
          SELECT format('COMMENT ON DATABASE %I IS %L', current_database(), shobj_description(oid, 'pg_database'))
          FROM pg_database WHERE datname = $1
          """,
          [config[:database]]
        )

      Postgrex.query!(conn, restore_comment, [])
      assert_raise RuntimeError, ~r/not provisioned/, fn -> Database.require_fixture!(conn, :unit) end
    end)
  end

  test "an upgrade test never reuses an existing database" do
    config = isolated_database()
    :ok = Database.provision!(config, :upgrade)
    on_exit(fn -> drop(config) end)

    with_connection(config, fn conn ->
      assert :ok = Database.require_fixture!(conn, :upgrade)
      assert_raise RuntimeError, ~r/not provisioned/, fn -> Database.require_fixture!(conn, :unit) end
    end)

    assert_raise RuntimeError, ~r/already_up/, fn -> Database.provision!(config, :upgrade) end
  end

  defp isolated_database do
    name = "brando_fixture_" <> Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)
    Repo.config() |> Keyword.delete(:url) |> Keyword.put(:database, name)
  end

  defp with_connection(config, fun) do
    {:ok, conn} =
      config
      |> Keyword.take([:hostname, :port, :socket_dir, :username, :password, :database, :ssl, :parameters])
      |> Postgrex.start_link()

    try do
      fun.(conn)
    after
      GenServer.stop(conn)
    end
  end

  defp drop(config), do: Ecto.Adapters.Postgres.storage_down(config)

  test "an upgrade test's database is named after the test database, with a random suffix" do
    name = Database.upgrade_database("brando_test")

    assert name =~ ~r/^brando_test-villain-[0-9a-f]{8}$/
    assert Database.upgrade_database?(name, "brando_test")
    refute Database.upgrade_database("brando_test") == name
  end

  test "a worktree's test database is not taken for an upgrade test's" do
    # A worktree in a directory named villain_deadbeef
    refute Database.upgrade_database?("brando_test_villain_deadbeef", "brando_test")
    # A partition's
    refute Database.upgrade_database?(Database.upgrade_database("brando_test1"), "brando_test")
  end

  test "a long test database name leaves an upgrade database within 63 bytes, apart from its partitions'" do
    database = "brando_test_" <> String.duplicate("x", 51)
    name = Database.upgrade_database(database)
    partition = Database.upgrade_database(database <> "1")

    assert byte_size(name) <= 63
    assert name =~ ~r/-villain-[0-9a-f]{8}$/
    assert Database.upgrade_database?(name, database)
    refute Database.upgrade_database?(partition, database)
    refute Database.upgrade_database?(name, database <> "1")
  end

  test "a multibyte name is cut between characters" do
    database = String.duplicate("ø", 30)

    assert String.valid?(Database.upgrade_database(database))
    assert byte_size(Database.upgrade_database(database)) <= 63
  end
end

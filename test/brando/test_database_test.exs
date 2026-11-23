defmodule Brando.Test.DatabaseTest do
  use ExUnit.Case, async: true

  alias Brando.Test.Database

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

defmodule Brando.Blueprint.MigrationsTest do
  use ExUnit.Case
  alias Brando.Blueprint.Migrations

  @test_opts [
    migration_path: "tmp/test_migrations",
    snapshot_path: "tmp/test_snapshots"
  ]

  setup do
    on_exit(fn ->
      File.rm_rf!("tmp/test_snapshots")
      File.rm_rf!("tmp/test_migrations")
    end)
  end

  test "initial migration" do
    Migrations.create_migration(Brando.MigrationTest.Project, @test_opts)
    assert [file] = Path.wildcard("tmp/test_migrations/*_brando_projects_project_001.exs")
    assert File.read!(file) == File.read!("test/support/migration_results/migration_001.txt")

    Migrations.create_migration(Brando.MigrationTest.ProjectUpdate1, @test_opts)
    assert [file] = Path.wildcard("tmp/test_migrations/*_brando_projects_project_002.exs")
    assert File.read!(file) == File.read!("test/support/migration_results/migration_002.txt")

    Migrations.create_migration(Brando.MigrationTest.ProjectUpdate2, @test_opts)
    assert [file] = Path.wildcard("tmp/test_migrations/*_brando_projects_project_003.exs")
    assert File.read!(file) == File.read!("test/support/migration_results/migration_003.txt")

    Migrations.create_migration(Brando.MigrationTest.Person, @test_opts)
    assert [file] = Path.wildcard("tmp/test_migrations/*_brando_persons_person_001.exs")
    assert File.read!(file) == File.read!("test/support/migration_results/migration_004.txt")
  end
end

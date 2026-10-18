defmodule Brando.Migration.IntrospectTest do
  use ExUnit.Case
  use Brando.ConnCase

  alias Brando.Migration.Introspect
  alias BrandoIntegration.Repo

  defmodule AsksDuringMigration do
    use Ecto.Migration

    alias Brando.Migration.Introspect

    def change do
      test = :persistent_term.get({__MODULE__, :test})

      send(test, {:answers, answers()})

      create table(:introspect_fresh) do
        add :name, :text
      end

      send(test, {:before_flush, Introspect.table_exists?(:introspect_fresh)})
      flush()
      send(test, {:after_flush, Introspect.column_exists?(:introspect_fresh, :name)})
    end

    defp answers do
      %{
        table: Introspect.table_exists?("pages"),
        column: Introspect.column_exists?("pages", "title"),
        missing_table: Introspect.table_exists?("introspect_missing"),
        missing_column: Introspect.column_exists?("pages", "introspect_missing"),
        column_of_missing_table: Introspect.column_exists?("introspect_missing", "title")
      }
    end
  end

  test "outside a migration, answers for the repo and prefix given" do
    assert Introspect.table_exists?("pages", repo: Repo)
    assert Introspect.table_exists?(:pages, repo: Repo, prefix: :public)
    assert Introspect.column_exists?(:pages, :title, repo: Repo)

    refute Introspect.table_exists?("introspect_missing", repo: Repo)
    refute Introspect.column_exists?("pages", "introspect_missing", repo: Repo)
    refute Introspect.column_exists?("introspect_missing", "title", repo: Repo)

    Repo.query!(~s(CREATE SCHEMA "introspect_elsewhere"))
    Repo.query!(~s[CREATE TABLE "introspect_elsewhere".pages (id bigserial PRIMARY KEY)])

    assert Introspect.column_exists?("pages", "id", repo: Repo, prefix: "introspect_elsewhere")
    refute Introspect.column_exists?("pages", "title", repo: Repo, prefix: "introspect_elsewhere")
    refute Introspect.table_exists?("pages", repo: Repo, prefix: "introspect_missing")
  end

  test "inside a migration, uses its repo and sees what it has flushed" do
    :persistent_term.put({AsksDuringMigration, :test}, self())
    on_exit(fn -> :persistent_term.erase({AsksDuringMigration, :test}) end)

    version = System.unique_integer([:positive])
    :ok = Ecto.Migrator.up(Repo, version, AsksDuringMigration, log: false, migration_lock: false)

    assert_received {:answers, answers}

    assert answers == %{
             table: true,
             column: true,
             missing_table: false,
             missing_column: false,
             column_of_missing_table: false
           }

    assert_received {:before_flush, false}
    assert_received {:after_flush, true}
  end
end

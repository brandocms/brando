defmodule Brando.Migrations.Brando202AddPublicProfileToUsersTest do
  # Runs the upgrade template inside the sandbox transaction against a users
  # table rolled back to before it; Postgres DDL is transactional, so
  # everything is undone afterwards.
  use ExUnit.Case
  use Brando.ConnCase

  alias BrandoIntegration.Repo

  @template Application.app_dir(
              :brando,
              "priv/templates/brando.upgrade/migrations/brando_202_add_public_profile_to_users.exs"
            )

  defp rows(sql, params \\ []), do: Repo.query!(sql, params).rows

  defp columns do
    "SELECT column_name FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'users'"
    |> rows()
    |> List.flatten()
  end

  defp run_template do
    [{module, _bytecode}] = Code.compile_file(@template)

    try do
      Ecto.Migrator.up(Repo, System.unique_integer([:positive]), module, log: false, migration_lock: false)
    after
      :code.purge(module)
      :code.delete(module)
    end
  end

  test "adds the optional job title and profile links to users, empty for existing users" do
    Repo.query!("ALTER TABLE users DROP COLUMN job_title, DROP COLUMN same_as")

    [[id]] =
      rows("""
      INSERT INTO users (name, email, password, role, language, inserted_at, updated_at)
      VALUES ('Existing', 'existing@example.test', 'x', 'user', 'en', now(), now())
      RETURNING id
      """)

    run_template()

    assert "job_title" in columns()
    assert "same_as" in columns()
    assert rows("SELECT job_title, same_as FROM users WHERE id = $1", [id]) == [[nil, []]]
  end
end

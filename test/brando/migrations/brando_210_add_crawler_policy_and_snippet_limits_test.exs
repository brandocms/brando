defmodule Brando.Migrations.Brando210AddCrawlerPolicyAndSnippetLimitsTest do
  # Runs the upgrade templates inside the sandbox transaction against tables
  # rolled back to before them; Postgres DDL is transactional, so everything
  # is undone afterwards.
  use ExUnit.Case
  use Brando.ConnCase

  alias BrandoIntegration.Repo

  @templates Application.app_dir(:brando, "priv/templates/brando.upgrade/migrations")
  @tenant "tenant_acme_production"

  defp columns(schema, table) do
    "SELECT column_name FROM information_schema.columns WHERE table_schema = $1 AND table_name = $2"
    |> Repo.query!([schema, table])
    |> Map.fetch!(:rows)
    |> List.flatten()
  end

  defp run_template(file) do
    [{module, _bytecode}] = Code.compile_file(Path.join(@templates, file))

    try do
      Ecto.Migrator.up(Repo, System.unique_integer([:positive]), module, log: false, migration_lock: false)
    after
      :code.purge(module)
      :code.delete(module)
    end
  end

  test "brando_210 adds its columns in public and every tenant schema" do
    Repo.query!("ALTER TABLE sites_seos DROP COLUMN crawler_policy")
    Repo.query!("ALTER TABLE pages DROP COLUMN meta_nosnippet, DROP COLUMN meta_max_snippet")
    Repo.query!(~s(CREATE SCHEMA "#{@tenant}"))

    for table <- ~w(sites_seos pages) do
      Repo.query!(~s{CREATE TABLE "#{@tenant}".#{table} (LIKE public.#{table} INCLUDING DEFAULTS)})
    end

    run_template("brando_210_add_crawler_policy_and_snippet_limits.exs")

    for schema <- ["public", @tenant] do
      assert "crawler_policy" in columns(schema, "sites_seos")
      assert "meta_nosnippet" in columns(schema, "pages")
      assert "meta_max_snippet" in columns(schema, "pages")
    end
  end
end

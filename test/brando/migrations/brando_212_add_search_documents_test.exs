defmodule Brando.Migrations.Brando212AddSearchDocumentsTest do
  # Runs the upgrade template inside the sandbox transaction, with the table
  # dropped first; Postgres DDL is transactional, so everything is undone.
  use ExUnit.Case
  use Brando.ConnCase

  alias BrandoIntegration.Repo

  @template Application.app_dir(:brando, "priv/templates/brando.upgrade/migrations/brando_212_add_search_documents.exs")

  defp run_template do
    [{module, _bytecode}] = Code.compile_file(@template)

    try do
      Ecto.Migrator.up(Repo, System.unique_integer([:positive]), module, log: false, migration_lock: false)
    after
      :code.purge(module)
      :code.delete(module)
    end
  end

  defp columns do
    Repo.query!(
      "SELECT column_name, data_type FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'search_documents'"
    ).rows
    |> Enum.sort()
  end

  defp indexes do
    Repo.query!("SELECT indexdef FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'search_documents'").rows
    |> List.flatten()
    |> Enum.sort()
  end

  test "creates the search index table as the schema and the indexer use it" do
    expected_columns = columns()
    expected_indexes = indexes()
    Repo.query!("DROP TABLE public.search_documents")

    run_template()

    assert columns() == expected_columns
    assert indexes() == expected_indexes
    assert Enum.any?(indexes(), &(&1 =~ "USING gin (document)"))

    fields = Brando.Search.Document.__schema__(:fields) |> Enum.map(&to_string/1)
    assert Enum.sort(["document" | fields]) == expected_columns |> Enum.map(&hd/1) |> Enum.sort()
  end
end

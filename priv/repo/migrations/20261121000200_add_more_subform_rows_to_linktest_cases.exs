defmodule BrandoIntegration.Repo.Migrations.AddMoreSubformRowsToLinktestCases do
  use Ecto.Migration

  # Embedded rows Ecto would not take back as a changeset, and rows an
  # entry's query leaves out (Brando.Blueprint.LinkOthersToTest)
  def change do
    alter table(:linktest_cases) do
      add :note, :jsonb
      add :aside, :jsonb
      add :archive, :jsonb
      add :extras, :jsonb
    end
  end
end

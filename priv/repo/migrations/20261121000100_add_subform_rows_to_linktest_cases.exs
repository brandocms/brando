defmodule BrandoIntegration.Repo.Migrations.AddSubformRowsToLinktestCases do
  use Ecto.Migration

  # Rich text in subform rows of a case, in its own column and in a table of
  # their own (Brando.Blueprint.LinkOthersToTest)
  def change do
    alter table(:linktest_cases) do
      add :highlights, :jsonb
      add :lead, :jsonb
    end

    create table(:linktest_chapters) do
      add :title, :text
      add :body, :text
      add :case_id, references(:linktest_cases, on_delete: :delete_all)
    end
  end
end

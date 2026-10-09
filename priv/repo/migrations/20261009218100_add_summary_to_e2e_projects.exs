defmodule BrandoIntegration.Repo.Migrations.AddSummaryToE2eProjects do
  use Ecto.Migration

  # The E2E Project blueprint's summary: rich text without Write with AI,
  # beside the introduction that turns it on.
  def change do
    alter table(:projects_projects) do
      add :summary, :text
    end
  end
end

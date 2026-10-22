defmodule BrandoIntegration.Repo.Migrations.AddLinktestCases do
  use Ecto.Migration

  # A case linked to the client's site when it has no page here
  # (`absolute_url ..., link_others_to:`; Brando.Blueprint.LinkOthersToTest).
  def change do
    create table(:linktest_cases) do
      add :title, :text
      add :slug, :text
      add :type, :text
      add :external_link, :text
      add :summary, :text
    end
  end
end

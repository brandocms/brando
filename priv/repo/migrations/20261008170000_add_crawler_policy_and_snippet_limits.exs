defmodule Brando.Repo.Migrations.AddCrawlerPolicyAndSnippetLimits do
  use Ecto.Migration

  # The SEO settings' AI crawler policy, and the snippet limits
  # `Brando.Trait.Meta` adds to pages and to the e2e Project blueprint.
  def change do
    alter table(:sites_seos) do
      add :crawler_policy, :map
    end

    for table <- [:pages, :projects_projects] do
      alter table(table) do
        add :meta_nosnippet, :boolean, default: false
        add :meta_max_snippet, :integer
      end
    end
  end
end

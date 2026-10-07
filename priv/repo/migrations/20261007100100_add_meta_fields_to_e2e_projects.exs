defmodule Brando.Repo.Migrations.AddMetaFieldsToE2eProjects do
  use Ecto.Migration

  # The e2e Project blueprint carries `Brando.Trait.Meta`.
  def change do
    alter table(:projects_projects) do
      add :meta_canonical_url, :text
    end
  end
end

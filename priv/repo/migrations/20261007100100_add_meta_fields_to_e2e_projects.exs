defmodule Brando.Repo.Migrations.AddMetaFieldsToE2eProjects do
  use Ecto.Migration

  # The e2e Project blueprint carries `Brando.Trait.Meta`.
  def change do
    alter table(:projects_projects) do
      add :meta_canonical_url, :text
      add :content_modified_at, :utc_datetime
    end
  end
end

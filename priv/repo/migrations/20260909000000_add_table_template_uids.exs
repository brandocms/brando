defmodule Brando.Repo.Migrations.AddTableTemplateUids do
  use Ecto.Migration

  def up do
    alter table(:content_table_templates) do
      add :uid, :text
    end

    execute "UPDATE content_table_templates SET uid = replace(gen_random_uuid()::text, '-', '') WHERE uid IS NULL"
    create unique_index(:content_table_templates, [:uid])
  end

  def down do
    drop unique_index(:content_table_templates, [:uid])
    alter table(:content_table_templates), do: remove(:uid)
  end
end

defmodule Brando.Repo.Migrations.AddTableTemplates do
  use Ecto.Migration

  def up do
    create table(:content_table_templates) do
      add :name, :text
      add :sequence, :integer
      add :creator_id, references(:users, on_delete: :nilify_all)

      timestamps()
    end

    alter table(:content_modules) do
      add :table_template_id, references(:content_table_templates, on_delete: :nilify_all)
    end

    create index(:content_modules, [:table_template_id])

    alter table(:content_vars) do
      add :table_template_id, references(:content_table_templates, on_delete: :delete_all)
    end

    create index(:content_vars, [:table_template_id])
  end

  def down do
    alter table(:content_modules) do
      remove :table_template_id
    end

    alter table(:content_vars) do
      remove :table_template_id
    end

    # remove index
    drop table(:content_table_templates)
  end
end

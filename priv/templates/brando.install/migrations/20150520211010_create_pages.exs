defmodule <%= application_module %>.Repo.Migrations.CreatePages do
  use Ecto.Migration
  use Brando.Villain, :migration

  def up do
    create table(:pages) do
      add :key,               :text, null: false
      add :language,          :text, null: false
      add :title,             :text, null: false
      add :slug,              :text, null: false
      villain
      add :status,            :integer
      add :parent_id,         references(:pages), default: nil
      add :creator_id,        references(:users)
      add :css_classes,       :text
      add :meta_description,  :text
      add :meta_keywords,     :text
      timestamps
    end
    create index(:pages, [:language])
    create index(:pages, [:slug])
    create index(:pages, [:key])
    create index(:pages, [:parent_id])
    create index(:pages, [:status])
  end

  def down do
    drop table(:pages)
    drop index(:pages, [:language])
    drop index(:pages, [:slug])
    drop index(:pages, [:key])
    drop index(:pages, [:parent_id])
    drop index(:pages, [:status])
  end
end

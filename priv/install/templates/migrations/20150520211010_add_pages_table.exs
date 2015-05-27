defmodule <%= application_module %>.Repo.Migrations.AddPagesTable do
  use Ecto.Migration

  def up do
    create table(:pages) do
      add :key,               :text
      add :language,          :text
      add :title,             :text
      add :slug,              :text
      add :data,              :json
      add :html,              :text
      add :status,            :integer
      add :parent_id,         references(:pages), default: nil
      add :creator_id,        references(:users)
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
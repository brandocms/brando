defmodule <%= application_module %>.Repo.Migrations.CreatePageFragments do
  use Ecto.Migration

  def up do
    create table(:pagefragments) do
      add :key,               :text
      add :language,          :text
      add :data,              :json
      add :html,              :text
      add :creator_id,        references(:users)
      timestamps
    end
    create index(:pagefragments, [:language])
    create index(:pagefragments, [:key])
  end

  def down do
    drop table(:pagefragments)
    drop index(:pagefragments, [:language])
    drop index(:pagefragments, [:key])
  end
end

defmodule <%= application_module %>.Repo.Migrations.AddPostsTable do
  use Ecto.Migration
  use Brando.Tag, :migration
  use Brando.Villain.Migration

  def up do
    create table(:posts) do
      add :language,          :text
      add :header,            :text
      add :slug,              :text
      add :lead,              :text
      villain
      add :cover,             :text
      add :status,            :integer
      add :creator_id,        references(:users)
      add :meta_description,  :text
      add :meta_keywords,     :text
      add :featured,          :boolean
      add :published,         :boolean
      add :publish_at,        :datetime
      tags
      timestamps
    end
    create index(:posts, [:language])
    create index(:posts, [:slug])
    create index(:posts, [:status])
    create index(:posts, [:tags])
  end

  def down do
    drop table(:posts)
    drop index(:posts, [:language])
    drop index(:posts, [:slug])
    drop index(:posts, [:status])
  end
end
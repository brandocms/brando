defmodule <%= application_module %>.Repo.Migrations.AddImagecategoriesTable do
  use Ecto.Migration
  def up do
    create table(:imagecategories) do
      add :name,              :text
      add :slug,              :text
      add :cfg,               :json
      add :creator_id,        references(:users)
      timestamps
    end
    create index(:imagecategories, [:slug])
    execute """
      INSERT INTO
        imagecategories
        (name, slug, cfg, creator_id, inserted_at, updated_at)
      VALUES
        ('post', 'post', '{"upload_path":"images/posts","sizes":{"xlarge":{"size":"900","quality":100},"thumb":{"size":"150x150^ -gravity center -extent 150x150","quality":100,"crop":true},"small":{"size":"300","quality":100},"medium":{"size":"500","quality":100},"large":{"size":"700","quality":100}},"size_limit":10240000,"random_filename":true,"default_size":"medium","allowed_mimetypes":["image/jpeg","image/png"]}', 1, NOW(), NOW());
    """
    execute """
      INSERT INTO
        imagecategories
        (name, slug, cfg, creator_id, inserted_at, updated_at)
      VALUES
        ('page', 'page', '{"upload_path":"images/pages","sizes":{"xlarge":{"size":"900","quality":100},"thumb":{"size":"150x150^ -gravity center -extent 150x150","quality":100,"crop":true},"small":{"size":"300","quality":100},"medium":{"size":"500","quality":100},"large":{"size":"700","quality":100}},"size_limit":10240000,"random_filename":true,"default_size":"medium","allowed_mimetypes":["image/jpeg","image/png"]}', 1, NOW(), NOW());
    """
  end

  def down do
    drop table(:imagecategories)
    drop index(:imagecategories, [:slug])
  end
end

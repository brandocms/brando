defmodule E2eProject.Migrations.Projects.Project.Blueprint001 do
  use Ecto.Migration

  def up do
    create table(:projects_projects) do
      add :publish_at, :utc_datetime
      add :status, :integer
      add :language, :text
      add :title, :text
      add :slug, :text
      add :full_case, :boolean
      add :introduction, :text
      add :meta_title, :text
      add :meta_description, :text
      add :sequence, :integer
      add :deleted_at, :utc_datetime
      timestamps()
      add :meta_image_id, references(:images, on_delete: :nilify_all)
      add :listing_image_id, references(:images, on_delete: :nilify_all)
      add :project_gallery_id, references(:galleries, on_delete: :nilify_all)
      add :creator_id, references(:users, on_delete: :nothing)
      add :client_id, references(:projects_clients, on_delete: :nothing)
      add :rendered_blocks, :text
      add :rendered_blocks_at, :utc_datetime
    end

    create index(:projects_projects, [:language])
    create unique_index(:projects_projects, [:slug])

    create table(:projects_alternates) do
      add :entry_id, references(:projects_projects, on_delete: :delete_all)
      add :linked_entry_id, references(:projects_projects, on_delete: :delete_all)
      timestamps()
    end

    create unique_index(:projects_alternates, [:entry_id, :linked_entry_id])

    create table(:projects_projects_related_entries_identifiers) do
      add :parent_id, references(:projects_projects, on_delete: :delete_all)
      add :identifier_id, references(:content_identifiers, on_delete: :delete_all)
      add :sequence, :integer
      timestamps()
    end

    create unique_index(:projects_projects_related_entries_identifiers, [:parent_id, :identifier_id])

    create table(:projects_projects_blocks) do
      add :entry_id, references(:projects_projects, on_delete: :delete_all)
      add :block_id, references(:content_blocks, on_delete: :delete_all)
      add :sequence, :integer
    end

    create unique_index(:projects_projects_blocks, [:entry_id, :block_id])
  end

  def down do
    drop table(:projects_projects)
    drop index(:projects_projects, [:language])
    drop unique_index(:projects_projects, [:slug])
    drop table(:projects_projects_alternates)
    drop table(:projects_projects_related_entries_identifiers)
    drop table(:projects_projects_blocks)
  end
end

defmodule Brando.Repo.Migrations.CreateVarTables do
  use Ecto.Migration

  def up do
    create table(:content_vars) do
      add :type, :text
      add :label, :text
      add :key, :text
      add :value, :text
      add :value_boolean, :boolean
      add :important, :boolean
      add :instructions, :text
      add :placeholder, :text
      add :color_picker, :boolean
      add :color_opacity, :boolean
      add :sequence, :integer
      add :options, :jsonb

      add :page_id, references(:pages, on_delete: :delete_all)
      add :block_id, references(:content_blocks, on_delete: :delete_all)
      add :module_id, references(:content_modules, on_delete: :delete_all)
      add :global_set_id, references(:sites_global_sets, on_delete: :delete_all)
      add :palette_id, references(:content_palettes, on_delete: :nilify_all)
      add :image_id, references(:images, on_delete: :nilify_all)
      add :file_id, references(:files, on_delete: :nilify_all)
      add :linked_identifier_id, references(:content_identifiers, on_delete: :nilify_all)
      add :creator_id, references(:users, on_delete: :nothing)

      timestamps()
    end

    create index(:content_vars, [:page_id])
    create index(:content_vars, [:block_id])
    create index(:content_vars, [:module_id])
    create index(:content_vars, [:global_set_id])
  end

  def down do
    drop table(:content_vars)
  end
end

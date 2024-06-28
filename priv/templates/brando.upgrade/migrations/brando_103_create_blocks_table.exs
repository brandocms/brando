defmodule Brando.Repo.Migrations.CreateBlocksTable do
  use Ecto.Migration

  def up do
    create table(:content_blocks) do
      add :uid, :text
      add :type, :text
      add :active, :boolean
      add :collapsed, :boolean
      add :description, :text
      add :anchor, :text
      add :multi, :boolean
      add :datasource, :boolean
      add :sequence, :integer
      add :source, :text
      add :rendered_html, :text
      add :rendered_at, :utc_datetime
      timestamps()
      add :module_id, references(:content_modules, on_delete: :delete_all)
      add :parent_id, references(:content_blocks, on_delete: :delete_all)
      add :palette_id, references(:content_palettes, on_delete: :nilify_all)
      add :creator_id, references(:users, on_delete: :nothing)
      add :refs, :jsonb
    end

    create index(:content_blocks, [:module_id])
    create index(:content_blocks, [:parent_id])

    create table(:content_block_identifiers) do
      add :sequence, :integer
      add :block_id, references(:content_blocks, on_delete: :delete_all)
      add :identifier_id, references(:content_identifiers, on_delete: :delete_all)
    end

    create unique_index(:content_block_identifiers, [:block_id, :identifier_id])

    villain_schemas = Brando.Villain.list_blocks()

    for {schema, attrs} <- villain_schemas,
        %{name: blocks_field} <- attrs do
      # create a join table
      table_name = schema.__schema__(:source)
      join_source = Enum.join([table_name, blocks_field], "_")

      create table(join_source) do
        add :entry_id, references(table_name, on_delete: :delete_all)
        add :block_id, references(:content_blocks, on_delete: :delete_all)
        add :sequence, :integer
      end

      create unique_index(join_source, [:entry_id, :block_id])

      alter table(table_name) do
        add :"rendered_#{blocks_field}", :text
        add :"rendered_#{blocks_field}_at", :utc_datetime
      end
    end
  end

  def down do
    drop table(:content_block_identifiers)

    villain_schemas = Brando.Villain.list_blocks()

    for {schema, attrs} <- villain_schemas,
        %{name: _} <- attrs do
      # create a join table
      table_name = schema.__schema__(:source)
      join_source = "#{table_name}_blocks"
      drop table(join_source)
    end

    drop table(:content_blocks)
  end
end

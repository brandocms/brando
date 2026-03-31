defmodule Brando.Repo.Migrations.CreateBlocksTable do
  use Ecto.Migration
  import Ecto.Query

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

    for {table, blocks_name} <- list_villain_tables() do
      create table(blocks_name) do
        add :entry_id, references(table, on_delete: :delete_all)
        add :block_id, references(:content_blocks, on_delete: :delete_all)
        add :sequence, :integer
      end

      create unique_index(blocks_name, [:entry_id, :block_id])

      # derive rendered column name from join table
      # e.g. "illustrators_biography" -> "rendered_biography"
      rendered_field = blocks_name |> String.replace("#{table}_", "")

      alter table(table) do
        add :"rendered_#{rendered_field}", :text
        add :"rendered_#{rendered_field}_at", :utc_datetime
      end
    end
  end

  def down do
    drop table(:content_block_identifiers)

    for {table, blocks_name} <- list_villain_tables() do
      drop table(blocks_name)
    end

    drop table(:content_blocks)
  end

  # Discovers villain data columns and derives block join table names.
  # "biography_data" -> join table "illustrators_biography"
  # "data" -> join table "illustrators_blocks"
  defp list_villain_tables do
    db_columns =
      Brando.repo().all(
        from("columns",
          prefix: "information_schema",
          select: [:table_name, :column_name],
          where: [table_schema: "public"],
          where: [data_type: "jsonb"]
        )
      )
      |> Enum.filter(&String.ends_with?(&1.column_name, "data"))
      |> Enum.reject(&(&1.table_name in ~w(revisions content_modules sites_globals pages_properties content_templates)))
      |> Enum.map(fn row ->
        blocks_rel =
          row.column_name
          |> String.replace("_data", "")
          |> then(fn
            "data" -> "blocks"
            other -> other
          end)

        {row.table_name, "#{row.table_name}_#{blocks_rel}"}
      end)

    # Include brando internal schemas that also have blocks
    db_columns ++ [{"content_templates", "content_templates_blocks"}]
  end
end

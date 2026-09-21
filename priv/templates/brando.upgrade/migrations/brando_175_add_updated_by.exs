defmodule Brando.Migrations.AddUpdatedBy do
  use Ecto.Migration

  @tables ~w(
    content_blocks
    content_module_sets
    content_palettes
    content_table_templates
    content_templates
    content_vars
    files
    galleries_gallery_objects
    images
    navigation_items
    navigation_menus
    pages
    pages_fragments
    sites_global_sets
    sites_previews
    videos
  )a

  def up do
    for table <- @tables do
      alter table(table) do
        add :updated_by_id, references(:users, on_delete: :nilify_all)
        add :edited_at, :utc_datetime
      end

      create index(table, [:updated_by_id])
    end

    flush()

    # edited_at is an upper bound for rows that predate the column; updated_by
    # is deliberately left empty rather than guessed from creator_id.
    for table <- @tables do
      execute "UPDATE #{table} SET edited_at = updated_at WHERE edited_at IS NULL"
    end
  end

  def down do
    for table <- @tables do
      drop index(table, [:updated_by_id])

      alter table(table) do
        remove :updated_by_id
        remove :edited_at
      end
    end
  end
end

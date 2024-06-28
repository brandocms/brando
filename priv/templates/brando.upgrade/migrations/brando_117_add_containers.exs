defmodule Brando.Repo.Migrations.AddContainers do
  use Ecto.Migration

  def up do
    create table(:content_containers) do
      add :name, :string
      add :namespace, :string
      add :help_text, :text
      add :code, :text
      add :type, :string
      add :allow_custom_palette, :boolean, default: false
      add :palette_namespace, :string
      add :palette_id, references(:content_palettes, on_delete: :nilify_all)
      add :deleted_at, :utc_datetime
      add :sequence, :integer
      timestamps()
    end

    create index(:content_containers, [:namespace])
  end

  def down do
    drop table(:content_containers)
  end
end

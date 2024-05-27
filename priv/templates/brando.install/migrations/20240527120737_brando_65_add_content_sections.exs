defmodule Brando.Repo.Migrations.AddContentSections do
  use Ecto.Migration

  def up do
    create table(:content_sections) do
      add :name, :text
      add :namespace, :text
      add :instructions, :text
      add :class, :text
      add :color_bg, :text
      add :color_fg, :text
      add :css, :text
      add :rendered_css, :text
      add :sequence, :integer
      add :deleted_at, :utc_datetime
      timestamps()
      add :creator_id, references(:users, on_delete: :nothing)
    end
  end

  def down do
    drop table(:content_sections)
  end
end

defmodule Brando.Repo.Migrations.AddContentTemplates do
  use Ecto.Migration
  import Ecto.Query

  def change do
    create table(:content_templates) do
      add :name, :text
      add :namespace, :text
      add :data, :jsonb
      add :html, :text
      add :instructions, :text
      add :sequence, :integer

      add :deleted_at, :utc_datetime
      add :creator_id, references(:users, on_delete: :nothing)

      timestamps()
    end
  end
end

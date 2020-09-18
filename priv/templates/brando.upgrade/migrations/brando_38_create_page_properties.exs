defmodule Brando.Migrations.CreatePageProperties do
  use Ecto.Migration

  def change do
    create table(:pages_properties) do
      add :key, :string
      add :label, :text
      add :type, :string
      add :data, :jsonb
      add :page_id, references(:pages_pages, on_delete: :delete_all)
    end
  end
end

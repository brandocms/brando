defmodule Brando.Repo.Migrations.CreateContentIdentifiers do
  use Ecto.Migration
  import Ecto.Query

  def change do
    create table(:content_identifiers) do
      add(:entry_id, :id)
      add(:schema, :string)
      add(:title, :text)
      add(:status, :integer)
      add(:language, :string)
      add(:cover, :string)
      add(:updated_at, :utc_datetime)
    end

    create(unique_index(:content_identifiers, [:entry_id, :schema]))
  end
end

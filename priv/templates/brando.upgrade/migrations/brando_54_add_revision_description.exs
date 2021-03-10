defmodule Brando.Repo.Migrations.AddRevisionDescription do
  use Ecto.Migration

  def change do
    alter table(:revisions) do
      add :description, :text
    end
  end
end

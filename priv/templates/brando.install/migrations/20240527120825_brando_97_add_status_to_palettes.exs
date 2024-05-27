defmodule Brando.Repo.Migrations.AddStatusToPalettes do
  use Ecto.Migration

  def change do
    alter table(:content_palettes) do
      add :status, :integer, default: 1
    end
  end
end

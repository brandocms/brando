defmodule Brando.Migrations.AddMetaTitleToPages do
  use Ecto.Migration
  use Brando.Sequence.Migration

  def change do
    alter table(:pages_pages) do
      add :meta_title, :text
    end
  end
end

defmodule Brando.Repo.Migrations.AddURLtoIdentifier do
  use Ecto.Migration

  def up do
    alter table(:content_identifiers) do
      add :url, :text
    end
  end

  def down do
    alter table(:content_identifiers) do
      remove :url
    end
  end
end

defmodule Brando.Repo.Migrations.AddFragmentsToPages do
  use Ecto.Migration

  def change do
    alter table(:pagefragments) do
      add :page_id, references(:pages)
    end
  end
end

defmodule Brando.Repo.Migrations.AddTitlesToFragments do
  use Ecto.Migration

  def change do
    alter table(:pages_fragments) do
      add :title, :text
    end
  end
end

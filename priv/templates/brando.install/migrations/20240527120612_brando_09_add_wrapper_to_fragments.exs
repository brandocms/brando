defmodule Brando.Repo.Migrations.AddWrapperToFragments do
  use Ecto.Migration

  def change do
    alter table(:pages_fragments) do
      add :wrapper, :text
    end
  end
end

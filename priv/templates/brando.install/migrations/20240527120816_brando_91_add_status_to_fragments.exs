defmodule Brando.Repo.Migrations.AddStatusToFragments do
  use Ecto.Migration

  def change do
    alter table(:pages_fragments) do
      add :status, :integer, default: 1
    end
  end
end

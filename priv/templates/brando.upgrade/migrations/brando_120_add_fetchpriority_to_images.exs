defmodule Brando.Repo.Migrations.AddFetchpriorityToImages do
  use Ecto.Migration

  def up do
    alter table(:images) do
      add :fetchpriority, :string, default: "auto"
    end
  end

  def down do
    alter table(:images) do
      remove :fetchpriority
    end
  end
end

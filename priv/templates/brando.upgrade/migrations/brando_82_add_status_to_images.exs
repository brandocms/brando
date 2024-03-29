defmodule Brando.Repo.Migrations.AddStatusToImages do
  use Ecto.Migration

  def change do
    alter table(:images) do
      add :status, :string, default: "processed"
    end
  end
end

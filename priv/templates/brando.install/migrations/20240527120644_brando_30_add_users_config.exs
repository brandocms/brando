defmodule Brando.Migrations.AddUsersConfig do
  use Ecto.Migration

  def change do
    alter table(:users_users) do
      add :config, :map, default: %{}
    end
  end
end

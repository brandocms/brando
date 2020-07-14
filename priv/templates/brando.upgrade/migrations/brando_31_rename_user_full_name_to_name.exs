defmodule Brando.Migrations.RenameUserFullNameToName do
  use Ecto.Migration

  def change do
    rename table(:users_users), :full_name, to: :name
  end
end

defmodule Brando.Integration.Migration do
  use Ecto.Migration
  def up do
    create table(:users) do
      add :username,      :text
      add :full_name,     :text
      add :email,         :text
      add :password,      :text
      add :avatar,        :text
      add :role,          :integer
      add :last_login,    :datetime
      timestamps
    end
    create index(:users, [:username], unique: true)
    create index(:users, [:email], unique: true)
  end

  def down do
    drop table(:users)
    drop index(:users, [:username], unique: true)
    drop index(:users, [:email], unique: true)
  end
end
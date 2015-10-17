defmodule <%= application_module %>.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def up do
    create table(:users) do
      add :username,      :text
      add :full_name,     :text
      add :email,         :text
      add :password,      :text
      add :avatar,        :text
      add :language,      :text,    default: "nb"
      add :role,          :integer
      add :last_login,    :datetime
      timestamps
    end
    create unique_index(:users, [:email])
    create unique_index(:users, [:username])
  end

  def down do
    drop table(:users)
    drop unique_index(:users, [:email])
    drop unique_index(:users, [:username])
  end
end

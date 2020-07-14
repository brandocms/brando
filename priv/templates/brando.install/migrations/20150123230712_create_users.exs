defmodule <%= application_module %>.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def up do
    create table(:users) do
      add :name,     :text
      add :email,         :text
      add :password,      :text
      add :avatar,        :jsonb
      add :language,      :text, default: "no"
      add :role,          :integer, default: 0
      add :active,        :boolean, default: true
      add :last_login,    :naive_datetime
      timestamps()
    end
    create unique_index(:users, [:email])
  end

  def down do
    drop table(:users)
    drop unique_index(:users, [:email])
  end
end

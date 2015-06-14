defmodule <%= application_module %>.Repo.Migrations.AddUsersTable do
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

    password = Brando.User.gen_password("admin")
    execute """
      INSERT INTO
        users
        ("username", "full_name", "email", "password", "avatar", "role", "last_login", "inserted_at", "updated_at")
      VALUES
        ('admin', 'Twined Admin', 'admin@twined.net', '#{password}', NULL, 7, NOW(), NOW(), NOW());
    """
  end

  def down do
    drop table(:users)
    drop index(:users, [:username], unique: true)
    drop index(:users, [:email], unique: true)
  end
end

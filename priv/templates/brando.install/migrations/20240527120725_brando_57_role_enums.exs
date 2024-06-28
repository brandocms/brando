defmodule Brando.Repo.Migrations.RoleEnums do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :new_role, :text
    end

    flush()

    execute """
    UPDATE
      users
    SET
      new_role = 'superuser'
    WHERE
      role = 3
    """

    execute """
    UPDATE
      users
    SET
      new_role = 'admin'
    WHERE
      role = 2
    """

    execute """
    UPDATE
      users
    SET
      new_role = 'editor'
    WHERE
      role = 1
    """

    execute """
    UPDATE
      users
    SET
      new_role = 'user'
    WHERE
      role = 0
    """

    flush()

    alter table(:users) do
      remove :role
    end

    flush()

    rename table(:users), :new_role, to: :role
  end

  def down do
    alter table(:users) do
      add :new_role, :integer
    end

    flush()

    execute """
    UPDATE
      users
    SET
      new_role = 3
    WHERE
      role = 'superuser'
    """

    execute """
    UPDATE
      users
    SET
      new_role = 2
    WHERE
      role = 'admin'
    """

    execute """
    UPDATE
      users
    SET
      new_role = 1
    WHERE
      role = 'editor'
    """

    execute """
    UPDATE
      users
    SET
      new_role = 0
    WHERE
      role = 'user'
    """

    flush()

    alter table(:users) do
      remove :role
    end

    flush()

    rename table(:users), :new_role, to: :role
  end
end

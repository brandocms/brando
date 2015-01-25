defmodule Brando.Integration.Migration do
  use Ecto.Migration

  def up do
    execute "CREATE TABLE users (
        id serial PRIMARY KEY,
        username text,
        full_name text,
        email text UNIQUE,
        password text,
        avatar text,
        role integer,
        last_login timestamp,
        inserted_at timestamp,
        updated_at timestamp)"

      execute "CREATE UNIQUE INDEX ON users (lower(username))"
  end

  def down do
    execute "DROP TABLE IF EXISTS users"
  end
end